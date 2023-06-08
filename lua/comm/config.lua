local _M = {
    _VERSION = '0.1'
}

_M.frp = {
    server = {
        timeout = 7,
        reqq_name='FRP_REQ',
        resq_name='FRP_RES'
    },
    client = {
        timeout = 5,
        server = 'ws://127.0.0.1:8200/ws'
    }
}

return _M