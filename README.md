# eztask
A task scheduler written in Lua

This library will work with any platform that uses Lua and abides with foreign asynchronous calls.

# How to use in LÖVE
```lua
local eztask=require "eztask"
eztask.tick=love.timer.getTime

--Bind events
local render=eztask.signal.new()

function love.update(dt) eztask:step(dt) end
function love.draw() render:invoke() end

eztask.thread.new(function(thread,arg1)
  local lib = thread:import "path/to/lib" --Or thread:import("path/to/lib","libname")
  
  --[[
  NOTE: Invoking the signal will create a new thread each time which may add overhead. If you do not wish 
  to create a new thread each time, pass a boolean as a second argument when attaching to the signal. You 
  can also have a single thread yield on the signal in a loop.
  ]]
  
  local render_callback=render:attach(function()
    lib.dosomething()
  end,true) --To disconnect the callback do render_callback:detach()
  
  --You can also do it this way, which may be better than the method above.
  local render_loop=thread.new(function()
    while thread:sleep(render) do
      lib.dosomething()
    end
  end)() --To kill the thread do render_loop:kill()
  
  --Creating a nested thread
  thread.new(function() --You do not need to redefine thread again
    while true do
      print(arg1)
      lib.doayield() --You can reference the parent thread's libraries instead of reimporting
    end
  end)()
  
  --[[
  NOTE: Any child threads or callback attachments made within a thread will prevent the thread from being 
  automatically deleted once the coroutine is killed. However, calling the kill() method will force all 
  child threads to be deleted and will detach all callbacks.
  
  If you wish to have the thread terminate itself, you can do thread._thread:kill()
  ]]
end)("hi")
```

# Creating a library
```lua
--[[
NOTE: You will need to sandbox the library if you wish to have access to the thread or if you are
returning another function.
]]

return function(thread)
  local somedependency      = thread:depend "somedependency"
  local someotherdependency = thread:depend "someotherdependency"

  local API={
    random_property=thread.eztask.property.new("hi")
  }

  API.random_property:attach(function(new,old)
    print(new,old)
  end)

  function API.dosomething()
    somedependency.doanotherthing()
    API.random_property.value="hello" --This will invoke a callback
  end

  function API.doayield() --This function will yield the current thread that called it
    thread:sleep(0.5)
  end

  return API
end
```
