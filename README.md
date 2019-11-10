# eztask
A task scheduler written in Lua

# How to use in LÖVE
```lua
local eztask=require "eztask"
eztask.tick=love.timer.getTime

--Bind native callback
local update=eztask:new_signal();function love.update(dt) eztask:step(dt) end
local render=eztask:new_signal();function love.draw() render:invoke() end

eztask:create_thread(function(thread,arg1)
  thread:import "path/to/lib" --Or thread:import("path/to/lib","libname")
  
  --[[
  NOTE: Invoking the signal will create a new thread each time. This may add overhead.
  If you do not wish create a thread, pass a boolean as a second argument when attaching
  to the callback.
  ]]
  local render_callback=render:attach(function() --You do not need to define thread again
    thread.lib.dosomething()
  end) --To disconnect callback do render_callback:detach()

  thread:create_thread(function() --You can create child threads
    while true do
      print(arg1)
      thread.lib:doayield() --You can reference the parent thread's libraries instead of reimporting
    end
  end):init()

  while thread:wait() do end --Keep the thread alive
end):init("hi")
```

# Creating a library
```lua
return function(thread) --You will need to sandbox the library if you wish to have access to the thread scope
  thread:depend "somedependency"
  thread:depend "someotherdependency"

  local API={}

  function API.dosomething()
    thread.somedependency.doanotherthing()
  end

  function API.doayield() --This function will yield the current thread that called it
    thread:sleep(0.5)
  end

  return API
end
```
