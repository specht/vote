require 'sinatra/base'
require 'faye/websocket'
require 'json'
require 'socket'
require 'openssl'
require 'timeout'
require 'yaml'
require 'digest/sha1'

class Main < Sinatra::Base
    @@clients = {}
    @@present_codes = {}
    @@votes = {}
    
    configure do
        salt = 'sdyBnCIfeUIXWkbiQagcId'
        @@codes = []
        STDERR.puts "Generating codes..."
        (0...100).each do |i|
            v = "#{salt}#{i}"
            code = Digest::SHA1.hexdigest(v).to_i(16).to_s(10)[0, 8]
            @@codes << code
        end
        if @@codes.size != @@codes.uniq.size
            STDERR.puts "Nope"
            exit(1)
        end
        @@moderator_code = @@codes[0]
        STDERR.puts @@codes.to_yaml
        STDERR.puts "Moderator code: #{@@moderator_code}"
        @@topic = nil
    end
    
    def broadcast_count()
        count = @@present_codes.select { |x, y| x != @@moderator_code }.size
        @@clients.each_pair do |id, ows|
            ows.send({:count => count}.to_json)
        end
    end
    
    def broadcast_start_topic(topic)
        @@clients.each_pair do |id, ows|
            ows.send({:start_topic => topic}.to_json)
        end
    end
    
    def broadcast_stop_topic()
        @@clients.each_pair do |id, ows|
            ows.send({:stop_topic => true}.to_json)
        end
    end
    
    def get_vote_results
        results = {}
        @@present_codes.each_pair do |code, client_id|
            vote = 'na'
            if code != @@moderator_code
                if @@votes[code]
                    vote = @@votes[code]
                end
                results[vote] ||= 0
                results[vote] += 1
            end
        end
        ['yes', 'no', 'abstention', 'na'].each do |k|
            results[k] ||= 0
        end
        
        results
    end
    
    def broadcast_vote_results()
        message = {:vote_results => get_vote_results()}.to_json
        @@clients.each_pair do |id, ows|
            ows.send(message)
        end
    end
    
    get '/ws' do
        if Faye::WebSocket.websocket?(request.env)
            ws = Faye::WebSocket.new(request.env)
            
            ws.on(:open) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@clients[client_id] = ws
                ws.send({:hello => 'world'}.to_json)
                broadcast_count()
            end

            ws.on(:close) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@clients.delete(client_id)
                @@present_codes.delete_if { |x, y| y == client_id }
                broadcast_count()
            end

            ws.on(:message) do |msg|
#                 STDERR.puts request.to_yaml
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                begin
                    request = {}
                    unless msg.data.empty?
                        request = JSON.parse(msg.data)
                    end
                    if request['verify_code']
                        code = request['verify_code']
                        login_ok = false
                        if @@codes.include?(code)
                            if (!@@present_codes.include?(code) || @@present_codes[code] == client_id)
                                ws.send({:code_valid => true, :moderator => code == @@moderator_code}.to_json)
                                @@present_codes[code] = client_id
                                login_ok = true
                                broadcast_count()
                                ws.send({:start_topic => @@topic}.to_json)
                                if @@topic
                                    ws.send({:vote_results => get_vote_results}.to_json)
                                    if @@votes[code]
                                        ws.send({:voted => @@votes[code]}.to_json)
                                    end
                                end
                            end
                        end
                        unless login_ok
                            if @@present_codes[code]
                                ws.send({:code_valid => false, :already_present => true}.to_json)
                            else
                                ws.send({:code_valid => false}.to_json)
                            end
                            ws.close()
                        end
                    elsif request['start_topic']
                        @@topic = request['start_topic']
                        broadcast_start_topic(@@topic)
                        @@votes = {}
                        broadcast_vote_results()
                    elsif request['stop_topic']
                        @@topic = nil
                        broadcast_stop_topic()
                        @@votes = {}
                    elsif request['vote']
                        @@present_codes.select { |x, y| y == client_id }.each_pair do |code, client_id|
                            @@votes[code] = request['vote']
                        end
                        broadcast_vote_results()
                    end
                rescue StandardError => e
                    STDERR.puts e
                end
            end

            ws.rack_response
        end
    end
    
    post '/api' do
        {:hello => 'world', :clients => @@clients.keys}.to_json
    end
    
    get '/ws/boo' do
        'BOOO1!!!!'
    end
    
    run! if app_file == $0
end
