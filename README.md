# eztask
A task scheduler written in Lua

This library will work with any platform that uses Lua and abides with foreign asynchronous calls.

# Setting it up in LÖVE
```lua
local eztask=require "eztask"

eztask.tick=love.timer.getTime

function love.update()
  eztask.step()
end
```

# Creating threads
```lua
local ThreadA=eztask.thread.new(function()
  while true do
    print("Apples")
    eztask.sleep(1)
  end
end)

local ThreadB=eztask.thread.new(function()
  while true do
    print("Oranges")
    eztask.sleep(1)
  end
end)

ThreadA()
ThreadB()
```
To kill a thread, call the kill() method. Ex: ```ThreadA:kill()```

You can also kill the thread within itself. Doing so will yield preventing any further code from being executed.

# Spawning light threads
You can spawn "light threads" (aka: coroutine.wrap) either within or outside of a thread.
```lua
eztask.thread.new(function()
  coroutine.wrap(function()
    while true do
      print("Potatoes")
      eztask.sleep(1)
    end
  end)()
  
  while true do
    print("Yams")
    eztask.sleep(1)
  end
end)()

coroutine.wrap(function()
  while true do
    print("Bananas")
    eztask.sleep(1)
  end
end)()
```
It is important to note that creating a light thread inside a thread will mean its runtime is dependent of that parent thread. If the parent thread is killed, the light thread will also stop running.

# Creating signals
```lua
local TestSignal=eztask.signal.new()

local OnEvent=TestSignal:attach(function(...) --A light thread is spawned every time it's called
  print("Signal invoked:",...)
end)

TestSignal("Hello World!")
TestSignal("Goodbye World!")
```
To detach a callback, call the detach() method on the binding. Ex: ```OnEvent:detach()```

To detach all callbacks, call the detach() method on the signal. Ex: ```TestSignal:detach()```

You can also yield on signals by doing ```eztask.sleep(TestSignal)``` which will yield the current thread until the signal is invoked. It will also return any values passed to the signal.

# Creating properties
A property is similar to a signal except it invokes when the value has changed.
```lua
local TestProperty=eztask.property.new("Apple")

local OnChanged=TestProperty:attach(function(new,old)
  print(string.format("Property changed from %s to %s",old,new))
end)

TestProperty.value="Orange"
```
Detaching a property is the same as a signal.
