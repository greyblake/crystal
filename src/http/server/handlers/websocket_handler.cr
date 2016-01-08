require "base64"
require "openssl/sha1"
require "../../web_socket"

class HTTP::WebSocketHandler < HTTP::Handler
  def initialize(&@proc : WebSocketSession ->)
  end

  def call(context)
    if context.request.headers["Upgrade"]? == "websocket" && context.request.headers["Connection"]? == "Upgrade"
      key = context.request.headers["Sec-Websocket-Key"]
      accept_code = Base64.strict_encode(OpenSSL::SHA1.hash("#{key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))

      response = context.response
      response.status_code = 101
      response.headers["Upgrade"] = "websocket"
      response.headers["Connection"] = "Upgrade"
      response.headers["Sec-Websocket-Accept"] = accept_code
      response.upgrade do |io|
        ws_session = WebSocketSession.new(io)
        @proc.call(ws_session)
        ws_session.run
        io.close
      end
    else
      call_next(context)
    end
  end

  class WebSocketSession
    def initialize(io)
      @ws = WebSocket.new(io)
      @buffer = Slice(UInt8).new(4096)
      @current_message = MemoryIO.new
    end

    def on_message(&@on_message : String ->)
    end

    def on_close(&@on_close : String ->)
    end

    def send(message)
      @ws.send(message)
    end

    def send_masked(message)
      @ws.send_masked(message)
    end

    def run
      loop do
        info = @ws.receive(@buffer)
        case info.opcode
        when WebSocket::Opcode::TEXT
          @current_message.write @buffer[0, info.size]
          if info.final
            if handler = @on_message
              handler.call(@current_message.to_s)
            end
            @current_message.clear
          end
        when WebSocket::Opcode::CLOSE
          @current_message.write @buffer[0, info.size]
          if info.final
            if handler = @on_close
              handler.call(@current_message.to_s)
            end
            @current_message.clear
            break
          end
        end
      end
    end
  end
end
