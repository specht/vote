require 'sinatra/base'
require 'faye/websocket'
require 'json'
require 'socket'
require 'openssl'
require 'timeout'
require 'yaml'
require 'digest/sha1'
require 'prawn/qrcode'
require 'prawn/measurement_extensions'

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
        @@topic = nil

        Prawn::Document::new(:page_size => 'A4', :margin => [0, 0, 0, 0]) do
            y = 0
            x = 0
            
            @@codes.each.with_index do |code, _|
                bounding_box([x * 17.cm + 2.cm, 297.mm - y * 13.cm - 2.cm + 11.cm], width: 17.cm, height: 11.cm) do
                    stroke { rectangle [0, 0], 17.cm, 11.cm }
                    bounding_box([5.mm, -5.mm], width: 15.cm) do
                        font_size 14
                        
                        text '<b>Code für Online-Abstimmung am Gymnasium Steglitz</b>', inline_format: true
                        move_down 2.mm
                        text '<em>gültig für Abstimmungen am 2. September 2020</em>', inline_format: true
                        move_down 5.mm
                        if code == @@moderator_code
                            text "<b>MODERATOREN-CODE: #{code}</b>", inline_format: true
                            move_down 5.mm
                            text "Dieser Code ist <b>nicht</b> mit einem Stimmrecht verknüpft.", inline_format: true
                        else
                            text "Auf diesem Blatt finden Sie einen Code, mit dem Sie an\nOnline-Abstimmungen teilnehmen können. Ihre Stimme\nist anonym, weil Sie den Zettel selbst gewählt haben und\nsomit der Code nicht Ihrer Person zuzuordnen ist."
                            move_down 5.mm
                            text 'Um an der Abstimmung teilzunehmen, öffnen Sie bitte die folgende Webseite:'
                            move_down 5.mm
                            text '<b>https://abstimmung.gymnasiumsteglitz.de</b>', inline_format: true
                            move_down 5.mm
                            text "Geben Sie dort den Code <b>#{code}</b> ein. Oder scannen Sie den QR-Code, um automatisch angemeldet zu werden.", inline_format: true
                            move_down 5.mm
                            text "Bei Fragen zum Verfahren wenden Sie sich bitte an: specht@gymnasiumsteglitz.de.", inline_format: true
                        end
                    end
                    bounding_box([133.mm, -2.mm], width: 3.cm) do
                        print_qr_code("https://abstimmung.gymnasiumsteglitz.de/##{code}", :dot => 2.5, :stroke => false)
                    end
                    
                end
                x += 1
                if x >= 1
                    y += 1
                    if y >= 2
                        y = 0
                        start_new_page if _ < @@codes.size - 1
                    end
                    x = 0
                end
            end
            render_file("/raw/Codes.pdf")
        end
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
                broadcast_vote_results()
            end

            ws.on(:close) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@clients.delete(client_id)
                @@present_codes.delete_if { |x, y| y == client_id }
                broadcast_count()
                broadcast_vote_results()
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
