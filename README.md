# eztask
A task scheduler written in Lua

This library will work with any platform that uses Lua, including LÖVE, Corona, etc..

# Example Usage
```lua
local thread_a=eztask.thread.new(function(thread)
  while thread:sleep(1) do
    print("Apples")
  end
end)

local thread_b=eztask.thread.new(function(thread)
  while thread:sleep(0.5) do
    print("Oranges")
  end
end)

thread_a()
thread_b()
```

# How to use in LÖVE
```lua
local eztask=require "eztask"
eztask.tick=love.timer.getTime

--Bind native callback
local render=eztask.signal.new()

function love.update(dt) eztask:step(dt) end
function love.draw() render:invoke() end

eztask.thread.new(function(thread,arg1)
  thread:import "path/to/lib" --Or thread:import("path/to/lib","libname")
  
  --[[
  NOTE: Invoking the signal will create a new thread each time. This may add overhead. If you do not wish 
  to create a thread, pass a boolean as a second argument when attaching to the callback. Doing so will 
  also prevent you from accessing the parent thread's libraries.
  Also note any callback attachments within the thread without passing the boolean parameter will 
  automatically be detached once the thread is killed.
  ]]
  local render_callback=render:attach(function()
    thread.lib.dosomething()
  end) --To disconnect callback do render_callback:detach()

  --[[
  NOTE: While you can create child threads, it's recommended to just create a neighbor thread instead. This is 
  because the child thread will not resume until the parent thread resumes first. The only exception to this 
  are callbacks. However, that behavior may also change in the future.
  ]]
  thread.thread.new(function() --You do not need to redefine thread again
    while true do
      print(arg1)
      thread.lib.doayield() --You can reference the parent thread's libraries instead of reimporting
    end
  end)()
end)("hi")
```

# Creating a library
```lua
return function(thread) --You will need to sandbox the library if you wish to have access to the thread scope
  thread:depend "somedependency"
  thread:depend "someotherdependency"

  local API={
    random_property=thread.eztask.property.new("hi")
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
