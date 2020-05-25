# eztask
A task scheduler written in Lua

This library will work with any platform that uses Lua and abides with foreign asynchronous calls.

# Setting it up in LÖVE
```lua
local eztask=require "eztask"

eztask.tick=love.timer.getTime --This is optional

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
end)

local ThreadB=eztask.thread.new(function(thread)
  while true do
    print("Oranges")
    thread:sleep(1)
  end
end)

ThreadA()
ThreadB()
```
To kill a thread, call the kill() method. Ex: ```ThreadA:kill()```

You can also kill it within the thread itself. Ex: ```thread:kill()```

# Creating signals
```lua
local TestSignal=eztask.signal.new()

local OnEvent=TestSignal:attach(function(callback,...)
  print("Signal invoked!",...)
end)

TestSignal("Hello World!")
TestSignal("Goodbye World!")
```
To detach a callback, call the detach() method on the binding. Ex: ```OnEvent:detach()```

To detach all callbacks, call the detach() method on the signal. Ex: ```TestSignal:detach()```

You can also detach the callback within. Ex: ```callback:detach()```

# Creating properties
A property is derived from signal and invokes when the value has changed.
```lua
local TestProperty=eztask.property.new("Apple")

local OnChanged=TestProperty:attach(function(callback,new,old)
  print("Property changed!",new,old)
end)

TestProperty.value="Orange"
```
Detaching a property is the same as a signal.
