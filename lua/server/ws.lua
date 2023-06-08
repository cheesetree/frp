local server = require "resty.websocket.server"                     -- 加载 WebSocket 库
local cfg = require "comm.config"
local json = require "cjson"

local wb, err = server.new{                                         -- 创建服务器对象
    timeout = 5000,                                                 -- 超时时间 5 秒
    max_payload_len = 1024 * 64,                                    -- 数据帧最大 64KB
}

if not wb then                                                      -- 检查对象是否创建成功
    ngx.log(ngx.ERR, "failed to init: ", err)                       -- 记录错误日志
    ngx.exit(444)                                                   -- 无法运行 WebSocket 服务
end

local closeFlag = false;

local push = function ()
    while closeFlag == false do
        ngx.sleep(0.001)
        local msg = ngx.shared.frp_reqq:rpop(cfg.frp.server.reqq_name)
        if msg then
            wb:send_text(ngx.shared.frp_reqq_data:get(msg))
            ngx.shared.frp_reqq_data:delete(msg)
        end
    end
end

local co = ngx.thread.spawn(push)

local data, typ, bytes, err                                         -- 返回值使用的变量声明
while true do                                                       -- 无限循序提供服务
    data, typ, err = wb:recv_frame()                         -- 接受数据帧 
    if not data then                                                -- 检查是否接收成功
        if not string.find(err, "timeout", 1, true) then            -- 忽略超时错误
            ngx.log(ngx.ERR, "failed to recv: ", err)               -- 其他错误则记录日志
            ngx.exit(444)                                           -- 无法运行 WebSocket 服务
        end
    end
    if typ == "close" then                                          -- close 数据帧
        bytes, err = wb:send_close()
        closeFlag = true                            -- 发送 close 数据帧
        ngx.exit(0)                                                 -- 服务正常结束
    end
    if typ == "ping" then                                           -- ping 数据帧
        bytes, err = wb:send_pong()                                 -- 发送 pong 数据帧
    end
    if typ == "pong" then                                           -- pong 数据帧
        -- 忽略 pong 数据帧
    end
    if typ == "text" then                              -- 文本数据帧
        local result = json.decode(data)
        if type(result) == "table" then
            local ftype = result["type"]
            if "resp" == ftype then
                local resp_data =  result["content"]
                if type(resp_data) == "table" then
                    local reqid = resp_data["reqid"]
                    if reqid then
                        ngx.shared.frp_resq_data:safe_add(reqid,json.encode(resp_data))
                    else
                        ngx.log(ngx.ERR, "failed to get reqid: ", reqid)
                    end
                end
            elseif "sys" == type then
               local ctx =  result["content"]
               if type(ctx) == "table" then
                   for k,v in pairs(ctx) do
                       ngx.shared.frp_sys:set(v)
                   end

                   local octx = ngx.shared.frp_sys:get_keys()
                    for i=1,#octx do
                        if ctx[octx[i]] == nil then
                            ngx.shared.frp_sys:delete(octx[i])
                        end
                    end
               end
            else
                ngx.log(ngx.ERR, "failed to decode: ", data)
            end
        else
            ngx.log(ngx.ERR, "failed to decode: ", data)
        end
    end
    ngx.sleep(0.001)
end

-- ngx.thread.wait(co)
ngx.log(ngx.INFO, 'closing')
wb:send_close()