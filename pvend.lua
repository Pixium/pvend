--[[
COULD BE UNSTABLE, REPORT ISSUES AT
https://github.com/Pixium/pvend
]]

local kristPKey = nil   --required
local shopName = nil    --required
local item = {
  name = nil,           --required
  displayName = nil,    --required
  price = nil           --required
}

local shopsync = {
  enabled = false,
  shopsyncModem = peripheral.find("modem"),
  name = nil,
  description = nil,
  owner = nil,
  location = {
    coordinates = nil,
    description = nil,
    dimension = nil
  }
}

local version = "0.1"

function drawMonitor(monitor, address, stock, heartbeat)
  local w,h = monitor.getSize()

  local function drawCentered(y,text)
    monitor.setCursorPos(math.ceil(w/2-#text/2)+1,y)
    monitor.write(text)
  end

  monitor.setTextColor(colors.white)
  monitor.setBackgroundColor(colors.black)

  monitor.setTextColor(colors.purple)
  drawCentered(1,shopName)
  monitor.setTextColor(colors.white)

  monitor.setTextColor(colors.lime)
  monitor.setCursorPos(1,2)
  monitor.write("/pay "..address)
  monitor.setTextColor(colors.white)

  monitor.setTextColor(colors.orange)
  drawCentered(3, item.displayName)
  monitor.setTextColor(colors.white)

  monitor.setTextColor(colors.red)
  drawCentered(4,item.price.."kst/each")
  monitor.setTextColor(colors.white)

  if stock == 0 then
    monitor.setTextColor(colors.red)
  elseif stock <= 4 then
    monitor.setTextColor(colors.orange)
  else
    monitor.setTextColor(colors.lime)
  end
  drawCentered(5,"stock: "..stock)
  monitor.setTextColor(colors.white)

  monitor.setCursorPos(1,h-2)
  monitor.write("Only buy if bar")
  monitor.setCursorPos(1,h-1)
  monitor.write("is flashing vvv")
  if heartbeat then
    monitor.setTextColor(colors.black)
    monitor.setBackgroundColor(colors.white)
  end
  monitor.setCursorPos(1,h)
  monitor.write((" "):rep(w))
  monitor.setTextColor(colors.white)
  monitor.setBackgroundColor(colors.black)
end

function genShopsyncMessage(stock, address)
  return {
    type = "ShopSync",
    info = {
      name = shopsync.name or shopName,
      description = shopsync.description,
      owner = shopsync.owner,
      computerID = os.computerID(),
      software = {
        name = "pvend",
        version = version
      },
      location = shopsync.location
    },
    items = {
      {
        prices = {
          {
            value = item.price,
            currency = "KST",
            address = address
          }
        },
        item = {
          name = item.name,
          displayName = item.displayName,
          nbt = nil --TODO
        },
        dynamicPrice = false,
        stock = stock,
        madeOnDemand = false,
        requiresInteration = false
      }
    }
  }
end

local monitor = peripheral.wrap("top")
monitor.setTextScale(0.5)

--implement "Terminated" screen on monitor when terminated.

local kristly = require("kristly")

function coloredPrint(color,txt)
  local p = term.getTextColor()
  term.setTextColor(color)
  print(txt)
  term.setTextColor(p)
end

function split(str, sep)
  sep = sep or "%s"
  local ret, index = {}, 1
  for match in string.gmatch(str, "([^"..sep.."]+)") do
    ret[index] = match
    index = index + 1
  end
  return ret
end

function parseMeta(meta)
  local ret = {}

  local sp1 = split(meta,";")
  for _,v in ipairs(sp1) do
    local sp2 = split(v,"=")
    if #sp2 == 1 then
      ret[sp2[1]] = true
    else
      local key = sp2[1]
      table.remove(sp2, 1)
      ret[key] = table.concat(sp2,"=")
    end
  end

  return ret
end

function mkCrashLog(str)
  if not fs.exists("/crashlogs") then
    fs.makeDir("/crashlogs")
    local h = fs.open("/crashlogs/crash_"..os.date("%Y-%m-%dT%H_%M_%S").."."..string.format("%03d",math.floor(os.epoch("utc")%1000)).."Z", "w")
    h.write(str)
    h.close()
  end
end

if not fs.exists("/logs") then
  fs.makeDir("/logs")
end
local logFile = "/logs/log_"..os.date("%Y-%m-%dT%H_%M_%S").."."..string.format("%03d",math.floor(os.epoch("utc")%1000)).."Z"
local dataSize = 0

function writeLog(log)
  log = log .. "\n"

  if #log > 4096 then
    coloredPrint(colors.red, "Unable to write log, max length is 4096, log was "..#log)
    return
  end

  if #log+dataSize > 4096 then
    logFile = "/logs/log_"..os.date("%Y-%m-%dT%H_%M_%S").."."..string.format("%03d",math.floor(os.epoch("utc")%1000)).."Z"
    dataSize = 0
  end

  local h = fs.open(logFile,"a")
  h.write(log)
  dataSize = dataSize + #log
  h.close()

  local list = fs.list("/logs")
  if #list > 128 then
    for i=1,#list-128 do
      fs.delete("/logs/"..list[i])
    end
  end
end

function countStock()
  local count = 0

  for i=1,16 do
    local detail = turtle.getItemDetail(i)

    if detail and detail.name == item.name then
      count = count + detail.count
    end
  end

  return count
end

function dropItems(count)
  if countStock() < count then
    return false, "Not enough items in stock"
  end

  local totalDropped = 0

  for i=1,16 do
    local detail = turtle.getItemDetail(i)

    if detail and detail.name == item.name then
      local toDrop = math.min(count, detail.count)

      turtle.select(i)
      turtle.drop(toDrop)

      totalDropped = totalDropped + toDrop
      if totalDropped >= count then break end
    end
  end

  return true
end

if _G.vendingKristWS then
  print("Old kristly WS found, closing...")
  if _G.vendingKristWS.ws then
    local s,e = pcall(_G.vendingKristWS.ws.close)
    if not s then
      coloredPrint(colors.red,e)
    end
  end
  _G.vendingKristWS = nil
end
_G.vendingKristWS = kristly.websocket(kristPKey)

local krist = _G.vendingKristWS

local heartbeat = false
local stockCache = countStock()
local drawUI = false
local s,e = pcall(function()
  -- Verify auth
  local res = kristly.authenticate(kristPKey)

  if not res then error("Failed to authenticate on krist API: No response") end

  if res.ok == false or res.authed == false then
    error("Failed to authenticate on krist API:\n "..textutils.serialize(res))
  end
  local wallet = res.address
  -- End verify auth

  parallel.waitForAny(function()
    krist:start()
  end,
  function()
    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setCursorPos(1,1)
    monitor.write("STARTING")

    sleep(2.5)

    krist:subscribe("ownTransactions")
    krist:upgradeConnection(kristPKey)
    krist:simpleWSMessage("me")

    drawUI = true
    local lastShopsyncTransmit
    while true do
      local _,ev = os.pullEvent("kristly")
      if ev and ev.type == "KRISTLY-ERROR" then
        if ev.error ~= "DISCONNECTED. Terminated" then
          coloredPrint(colors.red,"Kristly error: "..tostring(ev.error))
          mkCrashLog(tostring(ev.error))
          coloredPrint(colors.red,"Rebooting in 5 seconds...")

          monitor.setTextColor(colors.red)
          monitor.setBackgroundColor(colors.black)
          monitor.clear()
          monitor.setCursorPos(1,1)
          monitor.write("ERROR")

          sleep(5)
          os.reboot()
        else
          return
        end
      elseif ev.type == "event" and ev.event == "transaction" and ev.transaction.to == wallet and ev.transaction.metadata then
        local log = "Transaction received from "..ev.transaction.from.."\n  value: "..ev.transaction.value.."\n  ".."meta: "..ev.transaction.metadata.."\n"

        local meta = parseMeta(ev.transaction.metadata)
        local refundAddress = meta["return"] or ev.transaction.from

        if not (meta.donate == "true") then --this doesnt seem to work?
          local stock = countStock()
          local itemsToDrop = math.min(stock, math.floor(ev.transaction.value/item.price))
          local refund = math.floor(ev.transaction.value-itemsToDrop*item.price)

          if stock == 0 then
            kristly.makeTransaction(kristPKey, refundAddress, refund, "message=This item is out of stock!")
            log = log .. "Stock: 0, refunding "..refund.."kst"
          else
            if refund > 0 then
              log = log .. "Overpaid by "..refund.." krist, refunding\n"
              kristly.makeTransaction(kristPKey, refundAddress, refund, "message=Here are the funds remaining after your purchase!")
            end

            dropItems(itemsToDrop)
            if not lastShopsyncTransmit or os.epoch("utc")-lastShopsyncTransmit >= 30000 then
              shopsync.shopsyncModem.transmit(9773,9773,genShopsyncMessage(stock-itemsToDrop, address))
              lastShopsyncTransmit = os.epoch("utc")
            end

            log = log .. "Dropped "..itemsToDrop.." items"
            stockCache = stock - itemsToDrop
            drawMonitor(monitor, wallet, stockCache, heartbeat)
          end
        else
          log = log .. "Transaction is donation"
        end

        writeLog(log)
      end
    end
  end, function()
    local i=0
    while true do
      while not drawUI do sleep() end
      heartbeat = not heartbeat
      if i%15 == 0 then
        stockCache = countStock()
        i=0
      end
      i = i + 1
      monitor.clear()
      drawMonitor(monitor, wallet, stockCache, heartbeat)
      sleep(1)
    end
  end, function()
    -- Shopsync
    while not shopsync.enabled do
      sleep(120)
    end

    while true do
      if not shopsync.shopsyncModem then
        error("Invalid/missing shopsync modem")
      end

      shopsync.shopsyncModem.transmit(9773,9773,genShopsyncMessage(countStock(), address))
      sleep(math.random(1,15)+15)
    end
  end)
end)

if not s then
  if e == "Terminated" then
    return
  end

  coloredPrint(colors.red,"Error: "..tostring(e))
  mkCrashLog(tostring(e))
  coloredPrint(colors.red,"Rebooting in 5 seconds...")

  monitor.setTextColor(colors.red)
  monitor.setBackgroundColor(colors.black)
  monitor.clear()
  monitor.setCursorPos(1,1)
  monitor.write("ERROR")

  sleep(5)
  os.reboot()
end