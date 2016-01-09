module Zlib
  class Inflate
    include IO

    def initialize(@input : IO, wbits = LibZ::MAX_BITS)
      @buf :: UInt8[8192] # input buffer used by zlib
      @stream = LibZ::ZStream.new
      @stream.zalloc = LibZ::AllocFunc.new { |opaque, items, size| GC.malloc(items * size) }
      @stream.zfree = LibZ::FreeFunc.new { |opaque, address| GC.free(address) }
      ret = LibZ.inflateInit2(pointerof(@stream), wbits, LibZ.zlibVersion, sizeof(LibZ::ZStream))
      check_error(ret)
    end

    def write(slice : Slice(UInt8))
      raise IO::Error.new "Can't write to InflateIO"
    end

    def read(slice : Slice(UInt8))
      raise IO::Error.new "closed stream" if closed?

      prepare_input_data

      @stream.avail_out = slice.size.to_u32
      @stream.next_out = slice.to_unsafe

      # if no data was read, and the stream is not finished keep inflating
      while perform_inflate != LibZ::STREAM_END && @stream.avail_out == slice.size.to_u32
        prepare_input_data
      end

      slice.size - @stream.avail_out
    end

    def close
      return if @closed
      @closed = true

      @input.close
    end

    def closed?
      @closed
    end

    def inspect(io)
      to_s(io)
    end

    private def prepare_input_data
      return if @stream.avail_in > 0
      @stream.next_in = @buf.to_unsafe
      @stream.avail_in = @input.read(@buf.to_slice).to_u32
    end

    private def perform_inflate
      flush = @stream.avail_in == 0 ? LibZ::Flush::FINISH : LibZ::Flush::NO_FLUSH
      ret = LibZ.inflate(pointerof(@stream), flush)
      check_error(ret)
      ret
    end

    private def check_error(err)
      msg = @stream.msg ? String.new(@stream.msg) : nil
      ZlibError.check_error(err, msg)
    end
  end
end
