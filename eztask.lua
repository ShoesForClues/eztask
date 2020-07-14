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
	_version = {2,4,8},
	threads  = {},
	tick     = os.clock
}

local callback = {}
local signal   = {}
local property = {}
local thread   = {}

function eztask.running()
	return eztask.threads[running()]
end

function eztask.step()
	for _,thread_ in pairs(eztask.threads) do
		if thread_.parent==eztask then
			thread_:resume()
		end
	end
end

--Callback
callback.__index=callback

function callback.new(event,call,instance)
	local callback_={
		event    = event,
		call     = call,
		instance = instance,
		thread   = eztask.running()
	}
	
	event.callbacks[#event.callbacks+1]=callback_
	
	if callback_.thread then
		callback_.thread.callbacks[callback_]=callback_
	end
	
	return setmetatable(callback_,callback)
end

function callback.detach(callback_)
	for i,callback__ in ipairs(callback_.event.callbacks) do
		if callback__==callback_ then
			callback__.event.callbacks[i]=false
		end
	end
	if callback_.thread then
		callback_.thread.callbacks[callback_]=nil
	end
end

function callback.__call(callback_,...)
	if callback_.instance then
		callback_.call(callback_.instance,...)
	else
		callback_.call(callback_,...)
	end
end

--Signal
signal.__index=signal

signal.attach=callback.new

function signal.new()
	return setmetatable({callbacks={}},signal)
end

function signal.detach(signal_)
	for i,callback_ in ipairs(signal_.callbacks) do
		if callback_ and callback_.thread then
			callback_.thread.callbacks[callback_]=nil
		end
	end
	signal_.callbacks={}
end

function signal.__call(signal_,...)
	for _,callback_ in ipairs(signal_.callbacks) do
		if callback_ then callback_(...) end
	end
	for i=#signal_.callbacks,1,-1 do
		if not signal_.callbacks[i] then
			remove(signal_.callbacks,i)
		end
	end
end

--Property
property.__index=function(property_,k)
	if k=="value" then
		return rawget(property_,"_value")
	end
	return signal[k]
end

property.__newindex=function(property_,k,v)
	if k=="value" then
		local old=rawget(property_,"_value")
		if v~=old then
			rawset(property_,"_value",v)
			property_(v,old)
		end
	else
		rawset(property_,k,v)
	end
end

property.__call=signal.__call

property.attach=callback.new

function property.new(value)
	return setmetatable({callbacks={},_value=value},property)
end

--Thread
thread.__index=thread

function thread.new(env)
	return setmetatable({
		env          = env,
		parent       = nil,
		running      = property.new(false),
		killed       = property.new(false),
		resume_state = false,
		start_tick   = 0,
		stop_tick    = 0,
		run_tick     = 0,
		usage        = 0,
		threads      = {},
		callbacks    = {}
	},thread)
end

function thread.__call(thread_,...)
	if thread_.coroutine and status(thread_.coroutine)~="dead" then
		thread_:kill()
	end
	
	thread_.parent        = eztask.running() or eztask
	thread_.coroutine     = create(thread_.env)
	thread_.killed.value  = false
	thread_.running.value = true
	thread_.start_tick    = thread_.parent:tick()
	thread_.stop_tick     = thread_.parent:tick()
	thread_.run_tick      = 0
	
	thread_.parent.threads[thread_.coroutine]=thread_
	eztask.threads[thread_.coroutine]=thread_
	
	local running_=thread_.running:attach(function(_,state)
		if state then
			thread_.start_tick=(
				thread_.start_tick
				+(thread_.parent:tick()-thread_.stop_tick)
			)
			for _,child in pairs(thread_.threads) do
				child.running.value=child.resume_state
			end
		else
			for _,child in pairs(thread_.threads) do
				child.resume_state=child.running.value
				child.running.value=false
			end
			thread_.stop_tick=thread_.parent:tick()
		end
	end)
	
	thread_.killed:attach(function(callback_,killed)
		if killed then
			running_:detach()
			callback_:detach()
		end
	end)
	
	thread_:resume(thread_,...)
	
	return thread_
end

function thread.kill(thread_)
	thread_.running.value=false
	
	for _,thread__ in pairs(thread_.threads) do
		thread__:kill()
	end
	for _,callback_ in pairs(thread_.callbacks) do
		callback_:detach()
	end
	
	thread_.parent.threads[thread_.coroutine]=nil
	eztask.threads[thread_.coroutine]=nil
	thread_.killed.value=true
	
	return thread_
end

function thread.tick(thread_)
	return thread_.parent:tick()-thread_.start_tick
end

function thread.resume(thread_,...)
	if not thread_.running.value then
		return
	end
	
	local resume_tick=thread_:tick()
	
	if status(thread_.coroutine)=="suspended" then
		if thread_.run_tick and thread_.run_tick<=thread_:tick() then
			thread_.run_tick=nil
			local success,ret=resume(thread_.coroutine,...)
			if not success then
				print(traceback(thread_.coroutine,ret))
			end
		end
	end
	if status(thread_.coroutine)=="dead" then
		if not next(thread_.callbacks) and not next(thread_.threads) then
			return thread_:kill()
		end
	end
	
	for _,thread__ in pairs(thread_.threads) do
		thread__:resume()
	end
	
	thread_.usage=thread_:tick()-resume_tick
end

function thread.sleep(_,t)
	local thread_=eztask.running()
	
	if t==nil or type(t)=="number" then
		thread_.run_tick=thread_:tick()+(t or 0)
	elseif getmetatable(t)==signal or getmetatable(t)==property then
		t:attach(function(callback_,...)
			callback_:detach()
			thread_.run_tick=thread_:tick()
			thread_:resume(...)
		end)
	else
		error("Invalid yield type: "..type(t))
	end
	
	return yield()
end

eztask.callback = callback
eztask.signal   = signal
eztask.property = property
eztask.thread   = thread

return eztask