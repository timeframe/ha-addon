# frozen_string_literal: true

# :nocov:
require "socket"
require "logger"
require "zlib"
require "extlz4"
require_relative "image_encoder"

# TCP server implementing the Visionect PV3 device protocol on port 11114.
#
# Protocol format (20-byte header, little-endian):
#   Bytes 0-3:   Protocol Version (uint32) = 3
#   Bytes 4-7:   Flags (uint32) = 0
#   Bytes 8-11:  Packet Type (uint32) = 1 (status)
#   Bytes 12-15: Payload Length (uint32)
#   Bytes 16-19: Checksum (uint32) = CRC32(payload) for server, device ID for device
#
# Payload sub-header (24 bytes):
#   Bytes 0-7:   Reserved / num_rects field
#   Bytes 8-11:  Inner data length (uint32)
#   Bytes 12-15: Capacity (uint32)
#   Bytes 16-19: Flags (uint32) - 0 normal, 1 final
#   Bytes 20-23: Reserved (zeros)
#
# Inner data starts at payload offset 24, contains device serial and TCLV parameters.

module VisionectProtocol
  HEADER_SIZE = 20
  SUB_HEADER_SIZE = 24
  PROTOCOL_VERSION = 3
  PACKET_TYPE_STATUS = 1

  # Serial encoding prefix found in all packets
  SERIAL_PREFIX = [0x2b, 0x00, 0x17, 0x00, 0x06].pack("C5")

  class Packet
    attr_accessor :version, :flags, :type, :payload

    def initialize(version: PROTOCOL_VERSION, flags: 0, type: PACKET_TYPE_STATUS, payload: nil)
      @version = version
      @flags = flags
      @type = type
      @payload = payload || String.new(encoding: "BINARY")
    end

    def checksum
      Zlib.crc32(@payload) & 0xFFFFFFFF
    end

    def to_binary
      header = [@version, @flags, @type, @payload.bytesize, checksum].pack("V5")
      header + @payload
    end

    def self.read_from(socket)
      header_data = read_exact(socket, HEADER_SIZE)
      return nil unless header_data

      version, flags, pkt_type, payload_len, _checksum = header_data.unpack("V5")

      payload = nil
      if payload_len > 0
        payload = read_exact(socket, payload_len)
        return nil unless payload
      end

      new(version: version, flags: flags, type: pkt_type, payload: payload || String.new(encoding: "BINARY"))
    end

    def extract_serial
      return nil unless @payload && @payload.bytesize > SUB_HEADER_SIZE + 12
      inner = @payload[SUB_HEADER_SIZE..]
      idx = inner.index(SERIAL_PREFIX)
      return nil unless idx

      serial_start = idx + SERIAL_PREFIX.bytesize
      # Read ASCII characters until a non-printable byte
      serial = +""
      while serial_start + serial.length < inner.bytesize
        byte = inner.getbyte(serial_start + serial.length)
        break unless byte && byte >= 0x20 && byte < 0x7F
        serial << byte.chr
      end
      serial.empty? ? nil : serial
    end

    private_class_method def self.read_exact(socket, size)
      buf = String.new(encoding: "BINARY")
      remaining = size
      while remaining > 0
        chunk = socket.readpartial(remaining)
        return nil if chunk.nil? || chunk.empty?
        buf << chunk
        remaining -= chunk.bytesize
      end
      buf
    rescue IOError, Errno::EINVAL, Errno::ECONNRESET
      nil
    end
  end

  class Server
    # Class-level store for pre-encoded 4bpp image data, populated by
    # Device#refresh_screenshot! so the protocol server never blocks on encoding.
    #
    # Each entry tracks current and previous images so the server can send
    # both display buffers the device needs for e-paper waveform computation.
    @image_store = {}
    @image_store_mutex = Mutex.new

    class << self
      def store_image(device_id, raw_4bpp)
        new_crc = Zlib.crc32(raw_4bpp) & 0xFFFFFFFF
        @image_store_mutex.synchronize do
          entry = @image_store[device_id]
          if entry
            if entry[:current_crc] != new_crc
              entry[:previous] = entry[:current]
              entry[:previous_crc] = entry[:current_crc]
              entry[:current] = raw_4bpp
              entry[:current_crc] = new_crc
              entry[:changed] = true
            end
          else
            @image_store[device_id] = {
              current: raw_4bpp,
              current_crc: new_crc,
              previous: nil,
              previous_crc: nil,
              changed: true
            }
          end
        end
      end

      def fetch_image(device_id)
        @image_store_mutex.synchronize do
          entry = @image_store[device_id]
          return nil unless entry
          entry[:current]
        end
      end

      def fetch_images(device_id)
        @image_store_mutex.synchronize do
          entry = @image_store[device_id]
          return nil unless entry
          result = entry.dup
          entry[:changed] = false
          result
        end
      end
    end

    def initialize(port: 11114, logger: nil)
      @port = port
      @logger = logger || Logger.new($stdout, level: Logger::INFO)
      @running = false
    end

    def start
      @running = true
      @server = TCPServer.new("0.0.0.0", @port)
      @logger.info "[Visionect] Server listening on port #{@port}"

      while @running
        begin
          client = @server.accept
          Thread.new(client) { |c| handle_connection(c) }
        rescue IOError
          break unless @running
        end
      end
    rescue => e
      @logger.error "[Visionect] Server error: #{e.message}"
    ensure
      @server&.close
    end

    def stop
      @running = false
      @server&.close
    end

    private

    def handle_connection(client)
      remote = "#{client.peeraddr[2]}:#{client.peeraddr[1]}"
      @logger.info "[Visionect] Connection from #{remote}"

      # Disable Nagle algorithm for low-latency response
      client.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      # 10-second receive timeout to prevent indefinite blocking
      client.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO,
        [10, 0].pack("l_2"))

      # Read device status packet
      device_pkt = Packet.read_from(client)
      unless device_pkt
        @logger.warn "[Visionect] #{remote}: Failed to read device packet"
        return
      end

      serial = device_pkt.extract_serial
      @logger.info "[Visionect] #{remote}: Device #{serial || "unknown"} connected (#{device_pkt.payload.bytesize}B status)"

      # Look up or create the device
      device = find_or_create_device(serial) if serial

      # Fetch current and previous image data for dual-buffer delivery
      images = device ? self.class.fetch_images(device.id) : nil

      # show confirmation code if device is pending
      if device&.pending_confirmation?
        confirmation_4bpp = generate_confirmation_image_4bpp(device)
        confirmation_crc = Zlib.crc32(confirmation_4bpp) & 0xFFFFFFFF
        config_pkt = build_status_response(serial)
        client.write(config_pkt)
        client.write(build_image_packet(serial, confirmation_4bpp, buffer_index: 1, image_crc: confirmation_crc))
        client.write(build_image_packet(serial, confirmation_4bpp, buffer_index: 2, image_crc: confirmation_crc))
        client.flush
        ack_pkt = Packet.read_from(client)
        @logger.info "[Visionect] #{remote}: Sent confirmation code image" if ack_pkt
        return
      end

      config_pkt = build_status_response(serial)

      if images
        current = images[:current]
        current_crc = images[:current_crc]
        previous = images[:previous]
        previous_crc = images[:previous_crc]
        changed = images[:changed]

        client.write(config_pkt)

        if changed && previous
          # Image changed and we have the old frame: send both buffers so the
          # device can compute the correct e-paper waveform for the transition.
          @logger.info "[Visionect] #{remote}: Image changed, sending buf1 (old) + buf2 (new)"
          client.write(build_image_packet(serial, previous, buffer_index: 1, image_crc: previous_crc))
        else
          # First image or refresh (no previous): send same image as both buffers.
          # VSS always sends dual buffers - the EPD needs old+new for waveform
          # computation. For initial delivery, both buffers carry the same image.
          @logger.info "[Visionect] #{remote}: Sending dual buffer (same image, full refresh)"
          client.write(build_image_packet(serial, current, buffer_index: 1, image_crc: current_crc))
        end
        client.write(build_image_packet(serial, current, buffer_index: 2, image_crc: current_crc))
        client.flush

        # Read device acknowledgment(s)
        ack_pkt = Packet.read_from(client)
        @logger.info "[Visionect] #{remote}: Device acknowledged" if ack_pkt
      else
        # No image available: send config only (device will reconnect later)
        @logger.info "[Visionect] #{remote}: No image available"
        client.write(config_pkt)
        client.flush
      end

      sleep 0.1
    rescue => e
      @logger.error "[Visionect] #{remote}: #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    ensure
      client&.close
      @logger.info "[Visionect] #{remote}: Connection closed"
    end

    def find_or_create_device(serial)
      Device.find_or_create_by_visionect_serial(serial).tap do |device|
        device.record_visionect_connection!
      end
    rescue => e
      @logger.error "[Visionect] DB error: #{e.message}"
      nil
    end

    def generate_confirmation_image_4bpp(device)
      width = device.display_width
      height = device.display_height
      title_size = [width, height].min / 15
      code_size = [width, height].min / 6
      sub_size = [width, height].min / 20

      png_data = nil
      MiniMagick.convert do |convert|
        convert.size "#{width}x#{height}"
        convert << "xc:white"
        convert.gravity "Center"
        convert.font "Helvetica"
        convert.pointsize title_size
        convert.annotate("+0-#{height / 6}", "Add this device to your")
        convert.annotate("+0-#{height / 10}", "Timeframe account:")
        convert.pointsize code_size
        convert.annotate("+0+#{height / 12}", device.confirmation_code)
        convert.pointsize sub_size
        convert.annotate("+0+#{height / 4}", "Enter this code at")
        convert.annotate("+0+#{height / 4 + sub_size + 10}", "your Timeframe dashboard")
        convert << "png:-"
        png_data = convert.call
      end

      VisionectProtocol::ImageEncoder.png_to_4bpp(png_data)
    end

    def build_serial_block(serial)
      SERIAL_PREFIX + serial.encode("BINARY")
    end

    def build_payload(inner_data, flags: 0, capacity: nil, num_rects: 0)
      inner_len = inner_data.bytesize
      capacity ||= inner_len + 4
      sub_header = [0, num_rects, inner_len, capacity, flags, 0].pack("V6")
      sub_header + inner_data
    end

    def build_status_response(serial)
      serial ||= "unknown"
      serial_block = build_serial_block(serial)

      marker = [0x01F0].pack("V")
      padding = [0x0000].pack("v")

      tclv_data = [
        0x10, 0x00, 0x13, 0x01, 0x04, 0x00, 0x10, 0x08,
        0x0D, 0x00, 0xB0, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00
      ].pack("C*")

      inner_data = marker + padding + serial_block + tclv_data
      payload = build_payload(inner_data, flags: 0)

      Packet.new(payload: payload).to_binary
    end

    def build_final_response(serial)
      serial ||= "unknown"
      serial_block = build_serial_block(serial)

      prefix = [0x00, 0x00, 0x00, 0x00].pack("C4")
      cmd_data = [
        0x00, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
      ].pack("C*")

      inner_data = prefix + serial_block + cmd_data
      payload = build_payload(inner_data, flags: 1, capacity: inner_data.bytesize)

      Packet.new(payload: payload).to_binary
    end

    # Build a complete image packet for one display buffer.
    #
    # E-paper displays need two buffers for waveform computation:
    #   buffer 1 = previous/current frame (what's on screen)
    #   buffer 2 = new frame (what to transition to)
    #
    # TCLV bytes vary per buffer index (derived from captured VSS traffic).
    # image_crc is CRC32 of the raw 4bpp data, used by the device for cache validation.
    def build_image_packet(serial, raw_4bpp, buffer_index:, image_crc:)
      serial ||= "unknown"
      serial_block = build_serial_block(serial)
      strips = VisionectProtocol::ImageEncoder.compress_strips(raw_4bpp)

      marker = [0x01F0].pack("V")
      padding = [0x0000].pack("v")
      crc_bytes = [image_crc].pack("V")

      # TCLV config varies by buffer index (from captured VSS traffic).
      # Buffer 1: mode=0x50, flags=0x10,0x00, vals=0x02,0x13
      # Buffer 2: mode=0x61, flags=0x01,0x0A, vals=0x33,0x00
      tclv_data = if buffer_index == 1
        [
          0x10, 0x00, 0xB0, 0x05, 0x00, 0x00, 0x00, 0x01,
          0x00, 0x00, 0x00, 0x2C, 0xA6, 0x0E, 0x0F, 0x00,
          0x50, 0x00
        ].pack("C*") + crc_bytes + [
          0x10, 0x00, 0x00, 0x02, 0x00, 0x13, 0x18, 0x14,
          0x00, 0x04, 0x10, 0x00, 0x90, 0x40, 0x06, 0xB0,
          0x04, 0x02, 0x01, 0x02, 0x00, 0x04, 0x1D, 0x00,
          0x4F, 0xA6, 0x0E, 0x00
        ].pack("C*")
      else
        [
          0x10, 0x00, 0xB0, 0x05, 0x00, 0x00, 0x00, 0x02,
          0x00, 0x00, 0x00, 0x2C, 0xA6, 0x0E, 0x0F, 0x00,
          0x61, 0x00
        ].pack("C*") + crc_bytes + [
          0x01, 0x0A, 0x00, 0x33, 0x00, 0x00, 0x18, 0x14,
          0x00, 0x04, 0x10, 0x00, 0x90, 0x40, 0x06, 0xB0,
          0x04, 0x02, 0x01, 0x02, 0x00, 0x04, 0x1D, 0x00,
          0x4F, 0xA6, 0x0E, 0x00
        ].pack("C*")
      end

      # Protocol metadata tail (28 bytes, constant across buffers)
      inner_tail = [
        0xFF, 0x01, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x69, 0x50, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF
      ].pack("C*")

      inner_data = marker + padding + serial_block + tclv_data + inner_tail

      # Build rectangle data: strips 0-198 carry full 4800B of pixel data,
      # strip 199 carries only 80 bytes of 0xFF (matching VSS reference behavior)
      rect_data = String.new(encoding: Encoding::BINARY)
      strips.each_with_index do |compressed_strip, i|
        last_strip = (i == strips.length - 1)
        decomp_size = last_strip ? ImageEncoder::LAST_STRIP_SIZE : ImageEncoder::STRIP_SIZE
        rect_header = [
          i + 1,                     # 1-indexed strip number
          strips.length,             # total number of strips
          compressed_strip.bytesize, # compressed data length
          decomp_size,               # decompression buffer size
          0,                         # flags
          0                          # reserved
        ].pack("V6")
        rect_data << rect_header << compressed_strip
      end

      # Assemble payload: sub-header + inner_data + rectangles
      payload = build_payload(
        inner_data,
        flags: 0,
        num_rects: strips.length,
        capacity: ImageEncoder::STRIP_SIZE
      ) + rect_data

      Packet.new(payload: payload).to_binary
    end
  end
end
# :nocov:
