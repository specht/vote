require 'sinatra/base'
require 'faye/websocket'
require 'json'
require 'socket'
require 'openssl'
require 'yaml'

class Main < Sinatra::Base
#     use Rack::Auth::Basic, "Protected Area" do |username, password|
#       username == 'foo' && password == 'bar'
#     end

    @@clients = {}
    
    get '/ws' do
        if Faye::WebSocket.websocket?(request.env)
            ws = Faye::WebSocket.new(request.env)
            
            ws.on(:open) do |event|
                puts 'On Open'
            end

            ws.on(:message) do |msg|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                request = JSON.parse(msg.data)
                if request['action'] == 'open'
                    @@clients[client_id] = TCPSocket.new(request['host'], request['port'])
                    if true
                        ssl_context = OpenSSL::SSL::SSLContext.new()
#                         ssl_context.cert = OpenSSL::X509::Certificate.new(File.open("certificate.crt"))
#                         ssl_context.key = OpenSSL::PKey::RSA.new(File.open("certificate.key"))
                        ssl_context.ssl_version = :SSLv23
                        @@clients[client_id] = OpenSSL::SSL::SSLSocket.new(@@clients[client_id], ssl_context)
                        @@clients[client_id].sync_close = true
                        @@clients[client_id].connect
                    end
                    ws.send('OPENED')
                elsif request['action'] == 'send'
                    if @@clients[client_id]
                        @@clients[client_id].write(request['message'].strip)
                        @@clients[client_id].write("\r\n")
                    end
                elsif request['action'] == 'poll'
                    begin
                        buffer = @@clients[client_id].read_nonblock(1024)
                        ws.send(buffer)
                    rescue IO::EAGAINWaitReadable
                    rescue OpenSSL::SSL::SSLErrorWaitReadable
                    rescue EOFError
                        if @@clients[client_id]
                            @@clients.delete(client_id)
                        end
                        ws.send('CLOSE')
                    end
                end
            end

            ws.on(:close) do |event|
                puts 'On Close'
            end

            ws.rack_response
        end
    end
    
    post '/api' do
        {:hello => 'world'}.to_json
    end
    
    get '/boo' do
        'BOOO1!!!!'
    end
    
    run! if app_file == $0
end
