--[[
MIT License

Copyright (c) 2020 Shoelee

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local remove    = table.remove
local create    = coroutine.create
local resume    = coroutine.resume
local yield     = coroutine.yield
local status    = coroutine.status
local running   = coroutine.running
local traceback = debug.traceback

local eztask={
	_version  = {2,4,7},
	threads   = {},
	tick      = os.clock
}

local callback = {}
local signal   = {}
local property = {}
local thread   = {}

function eztask.running()
	return eztask.threads[running()]
end

function eztask.step()
	for _,_thread in pairs(eztask.threads) do
		if _thread.parent==eztask then
			_thread:resume()
		end
	end
end

--[Callback]
callback.__index=callback

callback.__call=function(_callback,...)
	_callback.call(_callback,...)
end

function callback.new(event,call)
	local _callback={
		event  = event,
		call   = call,
		thread = eztask.threads[running()]
	}
	
	event.callbacks[#event.callbacks+1]=_callback
	
	if _callback.thread then
		_callback.thread.callbacks[_callback]=_callback
	end
	
	return setmetatable(_callback,callback)
end

function callback.detach(_callback)
	for i=#_callback.event.callbacks,1,-1 do
		if _callback.event.callbacks[i]==_callback then
			remove(_callback.event.callbacks,i);break
		end
	end
	if _callback.thread then
		_callback.thread.callbacks[_callback]=nil
	end
end

--[Signal]
signal.__index=signal

signal.__call=function(_signal,...)
	for _,callback in pairs(_signal.callbacks) do
		callback(...)
	end
end

signal.attach=callback.new

function signal.new()
	return setmetatable({callbacks={}},signal)
end

function signal.detach(_signal)
	for i,_callback in pairs(_signal.callbacks) do
		if _callback.thread then
			_callback.thread.callbacks[_callback]=nil
		end
	end
	_signal.callbacks={}
end

--[Property]
property.__index=function(_property,k)
	if k=="value" then
		return rawget(_property,"_value")
	end
	return signal[k]
end

property.__newindex=function(_property,k,v)
	if k=="value" then
		local old=rawget(_property,"_value")
		if v~=old then
			rawset(_property,"_value",v)
			_property(v,old)
		end
	else
		rawset(_property,k,v)
	end
end

property.__call=signal.__call

property.attach=callback.new

function property.new(value)
	return setmetatable({callbacks={},_value=value},property)
end

--[Thread]
thread.__index=thread

thread.__call=function(_thread,...)
	if _thread.coroutine then
		_thread:kill()
	end
	
	_thread.parent        = eztask.threads[running()] or eztask
	_thread.killed.value  = false
	_thread.running.value = true
	_thread.start_tick    = eztask.tick()
	_thread.stop_tick     = 0
	_thread.tick          = 0
	_thread.run_tick      = 0
	_thread.coroutine     = create(_thread.env)
	
	_thread.parent.threads[_thread.coroutine]=_thread
	eztask.threads[_thread.coroutine]=_thread
	
	local _running=_thread.running:attach(function(_,state)
		if state then
			_thread.start_tick=_thread.start_tick+(eztask.tick()-_thread.stop_tick)
			for _,child in pairs(_thread.threads) do
				child.running.value=child.resume_state
			end
		else
			for _,child in pairs(_thread.threads) do
				child.resume_state=child.running.value
				child.running.value=false
			end
			_thread.stop_tick=eztask.tick()
		end
	end)
	
	_thread.killed:attach(function(_callback,killed)
		if killed then
			_running:detach()
			_callback:detach()
		end
	end)
	
	_thread:resume(_thread,...)
	
	return _thread
end

function thread.new(env)
	return setmetatable({
		running      = property.new(false),
		killed       = property.new(false),
		resume_state = false,
		start_tick   = 0,
		stop_tick    = 0,
		run_tick     = 0,
		tick         = 0,
		usage        = 0,
		parent       = nil,
		env          = env,
		threads      = {},
		callbacks    = {}
	},thread)
end

function thread.kill(_thread)
	_thread.running.value=false
	
	for _,child_thread in pairs(_thread.threads) do
		child_thread:kill()
	end
	for _,callback in pairs(_thread.callbacks) do
		callback:detach()
	end
	
	_thread.parent.threads[_thread.coroutine]=nil
	eztask.threads[_thread.coroutine]=nil
	_thread.coroutine=nil
	_thread.killed.value=true
	
	return _thread
end

function thread.resume(_thread,...)
	if status(_thread.coroutine)=="dead" then
		if next(_thread.callbacks)==nil and next(_thread.threads)==nil then
			return _thread:kill()
		end
	end
	if not _thread.running.value then
		return
	end
	
	local tick=eztask.tick()
	
	_thread.tick=tick-_thread.start_tick
	
	if status(_thread.coroutine)=="suspended" then
		if _thread.run_tick and _thread.run_tick<=_thread.tick then
			_thread.run_tick=nil
			local success,ret=resume(_thread.coroutine,...)
			if not success then
				print(traceback(_thread.coroutine,ret))
			end
		end
	end
	
	for _,child in pairs(_thread.threads) do
		child:resume()
	end
	
	_thread.usage=eztask.tick()-tick
end

function thread.sleep(_,t)
	local _type=type(t)
	local _thread=eztask.threads[running()]
	
	if t==nil or _type=="number" then
		_thread.run_tick=_thread.tick+(t or 0)
	elseif _type=="table" and (getmetatable(t)==signal or getmetatable(t)==property) then
		t:attach(function(_callback,...)
			_callback:detach()
			_thread.run_tick=_thread.tick
			_thread:resume(...)
		end)
	else
		error("Cannot yield thread with ".._type)
	end
	
	return yield()
end

eztask.callback = callback
eztask.signal   = signal
eztask.property = property
eztask.thread   = thread

return eztask