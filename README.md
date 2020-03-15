# eztask
A task scheduler written in Lua

This library will work with any platform that uses Lua and abides with foreign asynchronous calls.

# Setting it up in LÖVE
```lua
local eztask=require "eztask"

eztask.tick=love.timer.getTime

function love.update(dt)
  eztask:step(dt)
end
```

# Creating threads
```lua
local ThreadA=eztask.thread.new(function(thread)
  while true do
    print("Apples")
    thread:sleep(1)
  end
end)()

local ThreadB=eztask.thread.new(function(thread)
  while true do
    print("Oranges")
    thread:sleep(1)
  end
  
  --Create a nested thread.
  thread.new(function() --You do not need to redefine thread
    while true do
      print("Grapes")
      thread:sleep(1)
    end)
  end)()
end)()
```
To kill a thread, call the kill() method. Ex: ThreadA:kill()
You can also kill it within the thread itself. Ex: ``thread._thread:kill()``

# Creating signals
```lua
local TestSignal=eztask.signal.new()

local OnEvent=TestSignal:attach(function(thread,...)
  print("Signal invoked!",...)
end) --This creates a thread, pass a boolean as the second arg if you don't wish to.

eztask.thread.new(function(thread)
  TestSignal:invoke("Hello World!")
  thread:sleep(1)
  TestSignal:invoke("Goodbye World!")
end)()
```
To disconnect a signal, call the detach() method on the binding. Ex: OnEvent:detach()
To disconnect all signals, call the detach() method on the signal. Ex: TestSignal:detach()

# Creating properties
A property is derived from signal and invokes when the value has changed.
```lua
local TestProperty=eztask.property.new("Apple")

local OnChanged=TestProperty:attach(function(thread,new,old)
  print("Property changed!",new,old)
end)

TestProperty.value="Orange"
```
Disconnecting a property is the same as a signal.
