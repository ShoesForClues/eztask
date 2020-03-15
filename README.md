# eztask
A task scheduler written in Lua

This library will work with any platform that uses Lua and abides with foreign asynchronous calls.

# How to use in LÖVE
```lua
local eztask=require "eztask"

function love.update(dt)
  eztask:step(dt)
end

eztask.thread.new(function(thread)
  while true do
    print("Apples")
    thread:sleep(1)
  end
end)()

eztask.thread.new(function(thread)
  while true do
    print("Oranges")
    thread:sleep(1)
  end
end)()
```

# Creating signals
```lua
local TestSignal=eztask.signal.new()

local OnEvent=TestSignal:attach(function(...)
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

local OnChanged=TestProperty:attach(function(new,old)
  print("Property changed!",new,old)
end)

TestProperty.value="Orange"
```
Disconnecting a property is the same as a signal.
