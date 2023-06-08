local cfg = require "comm.config"
local json = require "cjson"
local http = require "resty.http"
local client = require "resty.websocket.client"
local wb, err = client:new()

local closeFlag = false;

local uri = cfg.frp.client.server
local ok, cerr = wb:connect(uri)
if not ok then
    ngx.log(ngx.ERR,"failed to connect: " .. cerr)
    return
end

local data, typ, bytes, err                                         -- 返回值使用的变量声明
local _switch_ws = {
    ["close"] = function(bytes, err)
        bytes, err = wb:send_close()
        closeFlag = true
        return false
    end,
    ["ping"] = function(bytes, err)
        local bytes, err = wb:send_pong()
        if not bytes then
            ngx.log(ngx.ERR,"failed to send frame: ", err)
            return true
        end
    end,
    ["pong"] = function(bytes, err)
    end,
    ["text"] = function(bytes, err)
        local result = json.decode(bytes)
        if type(result) == "table" then
            local ftype = result["type"]
            if "req" == ftype then
                local resp_data =  result["content"]
                if type(resp_data) == "table" then
                    local reqid = resp_data["reqid"]

                    local head = resp_data["head"]
                    if reqid  then
                        local httpc = http.new()
                        httpc:set_timeout(3000)
                        local res, herr = httpc:request_uri(
                        "http://10.116.0.51:30996",
                            {
                                path = "/file-service/token/get",
                                headers = head,
                                body = resp_data["body"] or {},
                                method = resp_data["method"] or "POST"
                          })

                          if herr then
                            ngx.log(ngx.ERR,"failed to send frame: ", reqid)
                            wb:send_text(json.encode({
                                ["type"]="resp",
                                ["content"]={["reqid"]=reqid,["err"]=herr,["status"]=500}
                            }
                            ))
                            return
                          end

                        if 200 ~= res.status then
                            wb:send_text(json.encode({
                                ["type"]="resp",
                                ["content"]={["reqid"]=reqid,["err"]=herr,["status"]=res.status}
                            }
                            ))
                            return
                        end
        
                         bytes, err = wb:send_text(json.encode({
                            ["type"]="resp",
                            ["content"]={["reqid"]=reqid,["body"]=res.body,["head"]=res.headers,["status"]=200}
                        }))

                        end
                end
            end
        end
    end,
    ["binary"] = function(bytes, err)
        ngx.log(ngx.INFO, "received a binary frame")
    end
}

local ping = function()
    while closeFlag ==false do
        ngx.sleep(60)
     local sbytes, serr = wb:send_ping()
     if not sbytes then
        ngx.log(ngx.ERR, "failed to send ping: ", serr)
        return
     end
 end
end

 local co = ngx.thread.spawn(ping)

while true do   
    local bytes, typ, err = wb:recv_frame()
    if not bytes then
        ngx.log(ngx.ERR, "failed to receive the frame: ", err)
    else 
        _switch_ws[typ](bytes, err)
    end
    ngx.sleep(0.001)
end

