var connected = null;
var ws = null;
var input = null;
var message_queue = [];
window.interval = null;
window.message_to_append = null;
window.message_to_append_index = 0;
window.message_to_append_timestamp = 0.0;

function teletype() {
    var messages = $('#messages');
    var div = messages.children().last();
    var t = Date.now() / 1000.0;
    while ((window.message_to_append_index < window.message_to_append.length) && window.message_to_append_index < (t - window.message_to_append_timestamp) * window.rate_limit)
    {
        var c = document.createTextNode(window.message_to_append.charAt(window.message_to_append_index));
        div.append(c);
        window.message_to_append_index += 1;
    }
    if (window.message_to_append_index >= window.message_to_append.length)
    {
        clearInterval(window.interval);
        window.interval = null;
        window.message_to_append = null;
        if (message_queue.length > 0)
            setTimeout(handle_message, 0);
    }
    $("html, body").stop().animate({ scrollTop: $(document).height() }, 0);
}

function handle_message()
{
    console.log('handle_message');
    if (message_queue.length === 0 || window.interval !== null || window.message_to_append !== null)
        return;
    var message = message_queue[0];
    message_queue = message_queue.slice(1);
    which = message.which;
    msg = message.msg;
    timestamp = message.timestamp;
    var messages = $('#messages');
    var div = messages.children().last();
    if ((which === 'note') || (which === 'error') || (!div.hasClass(which)))
    {
        div = $('<div>').addClass('message ' + which);
        messages.append(div);
        $('<div>').addClass('timestamp').html(timestamp).appendTo(div);
        if (which === 'server' || which == 'client')
            $('<div>').addClass('tick').appendTo(div);
    }
    if (which === 'server' || which === 'client')
    {
        window.message_to_append = msg;
        if (which === 'client')
            window.message_to_append += "\n";
        window.message_to_append_timestamp = Date.now() / 1000.0;
        window.message_to_append_index = 0;
        var d = 1000 / window.rate_limit;
        if (d < 1)
            d = 1;
        console.log(d);
        window.interval = setInterval(teletype, d);
    }
    else
    {
        div.append(document.createTextNode(msg));
        div.append("<br />");
        if (message_queue.length > 0)
            setTimeout(handle_message, 0);
    }
    
    $("html, body").stop().animate({ scrollTop: $(document).height() }, 400);
}

function append(which, msg)
{
    var d = new Date();
    var timestamp = ('0' + d.getHours()).slice(-2) + ':' +
                    ('0' + d.getMinutes()).slice(-2) + ':' +
                    ('0' + d.getSeconds()).slice(-2);
    message_queue.push({which: which, timestamp: timestamp, msg: msg});
    if (message_queue.length === 1)
        setTimeout(handle_message, 0);
}

function append_client(msg)
{
    append('client', msg);
}

function append_server(msg)
{
    append('server', msg);
}

function append_note(msg)
{
    append('note', msg);
}

function append_error(msg)
{
    append('error', msg);
}

function keepAlive() { 
    var timeout = 20000;  
    if (ws.readyState == ws.OPEN) {  
        ws.send('');  
    }  
    timerId = setTimeout(keepAlive, timeout);  
}                  

function setup_ws(ws)
{
    ws.onopen = function () {
        keepAlive();
    }
    
    ws.onclose = function () {
        $('.lost_connection_warning').show();
    }
    
    ws.onmessage = function (msg) {
        data = JSON.parse(msg.data);
        console.log(data);
        if (data.hello === 'world')
        {
            setup();
        }
        else if (typeof(data.code_valid) !== 'undefined')
        {
            if (data.code_valid) {
                $('.got-code').show();
                moderator = data.moderator;
                if (moderator) {
                    show_moderator();
                }
            } else {
                if (data.already_present)
                    $('.got-wrong-code').html('Der eingegebene Code ist bereits in Verwendung.');
                $('.got-wrong-code').show();
                $('.enter-code').show();
            }
        }
        else if (typeof(data.count) !== 'undefined')
        {
            $('.people-count').html('' + data.count);
        }
        else if (typeof(data.start_topic) !== 'undefined')
        {
            if (data.start_topic !== null) {
                $('.ti-topic').prop('disabled', true);
                $('.ti-topic').val(data.start_topic);
                $('.topic').text('Es wird abgestimmt über: ' + data.start_topic);
                $('.bu-yes').removeClass('btn-success').addClass('btn-outline-secondary').prop('disabled', false);
                $('.bu-no').removeClass('btn-danger').addClass('btn-outline-secondary').prop('disabled', false);
                $('.bu-abstention').removeClass('btn-warning').addClass('btn-outline-secondary').prop('disabled', false);
                $('.vote-results').show();
                if (moderator) {
                    $('.bu-start').prop('disabled', true);
                    $('.bu-stop').prop('disabled', false);
                }
            }
        }
        else if (typeof(data.stop_topic) !== 'undefined')
        {
            $('.ti-topic').prop('disabled', false).val('');
            $('.topic').html('<em>Die Abstimmung wurde beendet.</em>');
            $('.bu-yes').removeClass('btn-success').addClass('btn-outline-secondary').prop('disabled', true);
            $('.bu-no').removeClass('btn-danger').addClass('btn-outline-secondary').prop('disabled', true);
            $('.bu-abstention').removeClass('btn-warning').addClass('btn-outline-secondary').prop('disabled', true);
            $('.vote-results').hide();
            if (moderator) {
                $('.bu-start').prop('disabled', false);
                $('.bu-stop').prop('disabled', true);
            }
        }
        else if (typeof(data.vote_results) !== 'undefined')
        {
            for (let key in data.vote_results) {
                $('.count-' + key).text('' + data.vote_results[key]);
            }
        }
        else if (typeof(data.voted) !== 'undefined')
        {
            $('.bu-' + data.voted).click();
        }
    }
}

function sendInput()
{
    var msg = input.val();
    append_client(msg);
    ws.send(JSON.stringify({action: 'send', message: msg}))
    input.val("");
}

$(document).ready(function() {
    jQuery.get('/ws/boo', {}, function() {
        $('.head').fadeIn();
        $('.foot').fadeIn();
        connected = false;
        var ws_uri = 'ws://' + location.host + '/ws';
        if (location.host !== 'localhost:8020')
            ws_uri = 'wss://' + location.host + '/ws';
        console.log(ws_uri);
        ws = new WebSocket(ws_uri);
        setup_ws(ws);
        input = $('#input')

        input.keydown(function (e) {
            if (e.originalEvent.keyCode == 13)
            {
                e.preventDefault();
                sendInput();
            }
        });
    });
});
