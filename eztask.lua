--[[
MIT License

Copyright (c) 2020 ShoesForClues

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
local unpack    = unpack or table.unpack
local create    = coroutine.create
local resume    = coroutine.resume
local yield     = coroutine.yield
local status    = coroutine.status
local running   = coroutine.running
local traceback = debug.traceback

local eztask={
	_version  = {2,4,1},
	threads   = {},
	callbacks = {}
}

--Wrapped
eztask.tick = os.clock

--Object Types
local signal   = {}
local property = {}
local thread   = {}

eztask.__thread__=setmetatable({},{
	__index=function(_,k)
		local _thread=eztask.threads[running()]
		if _thread then
			if k=="_thread" then
				return _thread
			end
			return _thread[k]
		else
			return eztask[k]
		end
	end
})

------------------------------[Signal]------------------------------
signal.__index=signal

function signal.new()
	return setmetatable({callbacks={}},signal)
end

function signal.attach(_signal,call,no_thread)
	assert(type(call)=="function",("Cannot attach %s to callback."):format(type(call)))
	local callback={index=#_signal.callbacks+1,call=call}
	function callback:detach()
		for i=callback.index,1,-1 do
			if _signal.callbacks[i]==callback then
				remove(_signal.callbacks,i);break
			end
		end
		if callback.parent~=nil then
			callback.parent.callbacks[callback]=nil
		end
		eztask.callbacks[callback]=nil
	end
	_signal.callbacks[callback.index]=callback
	if not no_thread then
		local current_thread=eztask.threads[running()] or eztask
		callback.parent=current_thread
		current_thread.callbacks[callback]=callback
	end
	eztask.callbacks[callback]=callback
	return callback
end

function signal.invoke(_signal,...)
	for _,callback in pairs(_signal.callbacks) do
		if callback.parent then
			thread.new(callback.call,callback.parent)(...)
		else
			callback.call(eztask.__thread__,...)
		end
	end
end

function signal.detach(_signal)
	for _,callback in pairs(_signal.callbacks) do
		if callback.parent then
			callback.parent.callbacks[callback]=nil
		end
		eztask.callbacks[callback]=nil
	end
	_signal.callbacks={}
end

------------------------------[Property]------------------------------
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
			_property:invoke(v,old)
		end
	else
		rawset(_property,k,v)
	end
end

function property.new(value)
	return setmetatable({callbacks={},_value=value},property)
end

------------------------------[Thread]------------------------------
thread.__index=thread

thread.__call=function(_thread,...)
	if _thread.coroutine~=nil then
		_thread:kill()
	end
	_thread.killed.value=false
	_thread.running.value=true
	_thread.resume_state=true
	_thread.coroutine=create(_thread.env)
	_thread.parent.threads[_thread.coroutine]=_thread
	eztask.threads[_thread.coroutine]=_thread
	_thread:resume(0,...)
	return _thread
end

function thread.new(env,parent)
	assert(type(env)=="function",("Cannot create thread with %s"):format(type(env)))
	
	local _thread={
		running      = property.new(false),
		killed       = property.new(false),
		resume_state = false,
		tick         = 0,
		resume_tick  = 0,
		usage        = 0,
		parent       = parent or eztask.threads[running()] or eztask,
		env          = env,
		threads      = {},
		callbacks    = {}
	}
	
	_thread.running:attach(function(_,state)
		if state==true then
			for _,child in pairs(_thread.threads) do
				child.running.value=child.resume_state
			end
		else
			for _,child in pairs(_thread.threads) do
				child.resume_state=child.running.value
				child.running.value=false
			end
		end
	end,true)
	
	return setmetatable(_thread,thread)
end

function thread.sleep(_,d)
	local real_tick=eztask.tick()
	local d_type=type(d)
	local _thread=eztask.threads[running()]
	assert(_thread,"No thread to yield.")
	if d==nil or d_type=="number" then
		_thread.resume_tick=_thread.tick+(d or 0)
	elseif d_type=="table" and (getmetatable(d)==signal or getmetatable(d)==property) then
		local bind
		bind=d:attach(function()
			bind:detach()
			_thread.resume_tick=_thread.tick
			_thread:resume()
		end,true)
	else
		error("Cannot yield thread with "..d_type)
	end
	yield()
	return eztask.tick()-real_tick
end

function thread.resume(_thread,dt,...)
	if status(_thread.coroutine)=="dead" then
		if next(_thread.callbacks)==nil and next(_thread.threads)==nil then
			return _thread:kill()
		end
	end
	if _thread.running.value==true then
		dt=dt or 0
		local real_tick=eztask.tick()
		_thread.tick=_thread.tick+dt
		if status(_thread.coroutine)=="suspended" then
			if _thread.resume_tick and _thread.resume_tick<=_thread.tick then
				_thread.resume_tick=nil
				local success,err=resume(_thread.coroutine,eztask.__thread__,...)
				if not success then
					print("[ERROR]: "..traceback(_thread.coroutine,err))
				end
			end
		end
		for _,child in pairs(_thread.threads) do
			child:resume(dt)
		end
		_thread.usage=(eztask.tick()-real_tick)/dt
	end
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
end

function eztask:step(dt)
	for _,_thread in pairs(eztask.threads) do
		if _thread.parent==eztask then
			_thread:resume(dt)
		end
	end
end

eztask.signal   = signal
eztask.property = property
eztask.thread   = thread

return eztask