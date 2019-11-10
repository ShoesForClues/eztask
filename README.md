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

  --[[
  NOTE: While you can create child threads, it's recommended to just create a neighbor 
  thread instead. This is because the child thread will not resume until the parent 
  thread resumes first.
  ]]
  thread:create_thread(function()
    while true do
      print(arg1)
      thread.lib.doayield() --You can reference the parent thread's libraries instead of reimporting
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

  local API={
    random_property=thread.eztask:new_property("hi")
  }

  API.random_property:attach(function(new,old)
    print(new,old)
  end)

  function API.dosomething()
    thread.somedependency.doanotherthing()
    API.random_property.value="hello" --This will invoke a callback
  end

  function API.doayield() --This function will yield the current thread that called it
    thread:sleep(0.5)
  end

  return API
end
```
