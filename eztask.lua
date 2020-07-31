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

local t_remove    = table.remove
local t_clear     = table.clear       --LuaJIT 2.0.5

local c_create    = coroutine.create
local c_close     = coroutine.close   --Lua 5.4
local c_resume    = coroutine.resume
local c_yield     = coroutine.yield
local c_status    = coroutine.status
local c_running   = coroutine.running

local d_traceback = debug.traceback

-------------------------------------------------------------------------------

local eztask={
	version = {2,5,5},
	tick    = os.clock,
	threads = {},
	tasks   = {}
}

local callback = {}
local signal   = {}
local property = {}
local thread   = {}

-------------------------------------------------------------------------------

function eztask.step()
	for _,thread_ in pairs(eztask.threads) do
		if thread_.parent==eztask then
			eztask.resume(thread_)
		end
	end
	for task_,t in pairs(eztask.tasks) do
		if eztask:tick()>=t then
			eztask.tasks[task_]=nil
			eztask.resume(task_)
		end
	end
end

function eztask.sleep(t)
	local thread_=eztask.running or eztask
	local coroutine_=c_running()
	
	if t==nil or type(t)=="number" then
		if thread_.coroutine==coroutine_ then
			thread_.resume_tick=thread_:tick()+(t or 0)
		else
			thread_.tasks[coroutine_]=thread_:tick()+(t or 0)
		end
	else
		local callback_
		if thread_.coroutine==coroutine_ then
			callback_=t:attach(function(...)
				callback_:detach()
				thread_.resume_tick=thread_:tick()
				eztask.resume(thread_,...)
			end)
		else
			callback_=t:attach(function(...)
				callback_:detach()
				eztask.resume(coroutine_,...)
			end)
		end
	end
	
	return c_yield()
end

function eztask.resume(thread_,...)
	if type(thread_)=="thread" then
		local success,return_=c_resume(thread_,...)
		if not success then
			print(d_traceback(thread_,return_))
		end
		return success,return_
	else
		local top_thread=eztask.running
		resume_tick=thread_.parent:tick()
		eztask.running=thread_
		
		if
			c_status(thread_.coroutine)=="suspended"
			and thread_.resume_tick
			and thread_.resume_tick<=thread_:tick()
		then
			thread_.resume_tick=nil
			local _,return_=eztask.resume(thread_.coroutine,...)
			if return_=="kill" then
				eztask.running=top_thread
				return thread_:kill()
			end
		end
		
		for task_,t in pairs(thread_.tasks) do
			if thread_:tick()>=t then
				thread_.tasks[task_]=nil
				local _,return_=eztask.resume(task_)
				if return_=="kill" then
					eztask.running=top_thread
					return thread_:kill()
				end
			end
		end
		
		for _,thread__ in pairs(thread_.threads) do
			eztask.resume(thread__)
		end
		
		eztask.running=top_thread
	end
end

-------------------------------------------------------------------------------

function callback.new(event,call,instance,no_thread)
	local callback_={
		event    = event,
		call     = call,
		instance = instance
	}
	
	event.callbacks[#event.callbacks+1]=callback_
	
	if eztask.running and not no_thread then
		local thread_=eztask.running
		callback_.thread=thread_
		thread_.callbacks[callback_]=callback_
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
	if not callback_.thread or callback_.thread.running.value then
		if callback_.instance then
			callback_.call(callback_.instance,...)
		else
			callback_.call(...)
		end
	end
end

callback.__index=callback

-------------------------------------------------------------------------------

function signal.new()
	return setmetatable({callbacks={}},signal)
end

signal.attach=callback.new

function signal.detach(signal_)
	for i=#signal_.callbacks,1,-1 do
		local callback_=signal_.callbacks[i]
		if callback_ and callback_.thread then
			callback_.thread.callbacks[callback_]=nil
		end
		signal_.callbacks[i]=nil
	end
end

function signal.__call(signal_,...)
	for i=1,#signal_.callbacks do
		local callback_=signal_.callbacks[i]
		if callback_ then callback_(...) end
	end
	for i=#signal_.callbacks,1,-1 do
		if not signal_.callbacks[i] then
			t_remove(signal_.callbacks,i)
		end
	end
end

signal.__index=signal

-------------------------------------------------------------------------------

function property.new(value)
	return setmetatable({callbacks={},_value=value},property)
end

property.attach=callback.new

function property.detach(property_)
	for i=#property_.callbacks,1,-1 do
		local callback_=property_.callbacks[i]
		if callback_ and callback_.thread then
			callback_.thread.callbacks[callback_]=nil
		end
		property_.callbacks[i]=nil
	end
end

function property.__index(property_,k)
	if k=="value" then
		return rawget(property_,"_value")
	else
		return property[k]
	end
end

function property.__newindex(property_,k,v)
	if k=="value" then
		local old=rawget(property_,"_value")
		if v~=old then
			rawset(property_,"_value",v)
			for i=1,#property_.callbacks do
				local callback_=property_.callbacks[i]
				if callback_ then
					callback_(property_._value,old)
				end
			end
			for i=#property_.callbacks,1,-1 do
				if not property_.callbacks[i] then
					t_remove(property_.callbacks,i)
				end
			end
		end
	else
		rawset(property_,k,v)
	end
end

-------------------------------------------------------------------------------

function thread.new(env)
	return setmetatable({
		env          = env,
		parent       = nil,
		running      = property.new(false),
		active       = property.new(false),
		resume_state = false,
		start_tick   = 0,
		stop_tick    = 0,
		resume_tick  = 0,
		usage        = 0,
		threads      = {},
		tasks        = {},
		callbacks    = {}
	},thread)
end

function thread.__call(thread_,...)
	if thread_.active.value then
		thread_:kill()
	end
	
	local call_running,call_active
	
	thread_.parent        = eztask.running or eztask
	thread_.coroutine     = c_create(thread_.env)
	thread_.start_tick    = thread_.parent:tick()
	thread_.stop_tick     = thread_.start_tick
	thread_.resume_tick   = 0
	thread_.active.value  = true
	thread_.running.value = true
	
	thread_.parent.threads[thread_.coroutine]=thread_
	eztask.threads[thread_.coroutine]=thread_
	
	call_running=thread_.running:attach(function(state)
		if state then
			thread_.start_tick=(
				thread_.start_tick
				+(thread_.parent:tick()-thread_.stop_tick)
			)
			for _,child in pairs(thread_.threads) do
				child.running.value=child.resume_state
			end
		else
			thread_.stop_tick=thread_.parent:tick()
			for _,child in pairs(thread_.threads) do
				child.resume_state=child.running.value
				child.running.value=false
			end
			if thread_.coroutine==c_running() then
				c_yield()
			end
		end
	end,nil,true)
	
	call_active=thread_.active:attach(function(active)
		if not active then
			call_running:detach()
			call_active:detach()
		end
	end,nil,true)
	
	eztask.resume(thread_,...)
	
	return thread_
end

function thread.kill(thread_)
	if not thread_.coroutine then
		return
	end
	if thread_==eztask.running then
		return c_yield("kill")
	end
	
	if c_close then
		c_close(thread_.coroutine)
		for task_,t in pairs(thread_.tasks) do
			thread_.tasks[task_]=nil
			c_close(task_)
		end
	end
	
	thread_.running.value=false
	
	for _,thread__ in pairs(thread_.threads) do
		thread__:kill()
	end
	for _,callback_ in pairs(thread_.callbacks) do
		callback_:detach()
	end
	
	thread_.parent.threads[thread_.coroutine]=nil
	eztask.threads[thread_.coroutine]=nil
	
	thread_.active.value=false
	
	return thread_
end

function thread.tick(thread_)
	if thread_.running.value then
		return thread_.parent:tick()-thread_.start_tick
	else
		return thread_.stop_tick-thread_.start_tick
	end
end

thread.__index=thread

-------------------------------------------------------------------------------

eztask.callback = callback
eztask.signal   = signal
eztask.property = property
eztask.thread   = thread

return eztask