--[[
EZTask written by ShoesForClues Copyright (c) 2020

MIT License

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
	_version  = {2,1,8};
	imports   = {};
	threads   = {};
	callbacks = {};
}

eztask.imports.eztask=eztask --wtf
eztask._scope=setmetatable({},{
	__index=function(_,k)
		local _coroutine=running()
		if _coroutine then
			if k=="_thread" then
				return eztask.threads[_coroutine]
			end
			return eztask.threads[_coroutine][k] or eztask.threads[_coroutine].imports[k]
		else
			return eztask[k] or eztask.imports[k]
		end
	end
})

--Wrapped
eztask.require = require
eztask.tick    = os.clock

--Class Types
local signal   = {}
local property = {}
local thread   = {}

function eztask.import(_parent,source,name)
	assert(source~=nil,"Cannot import from nil")
	if name==nil then
		assert(type(source)=="string",("Cannot import %s without a name"):format(source))
		name=source:sub((source:match("^.*()/") or 0)+1,#source)
	else
		name=tostring(name)
	end
	local success,ret=pcall(eztask.require,source)
	if success then
		source=ret
	end
	if type(source)=="function" then
		source=source(eztask._scope)
	end
	if _parent.imports[name] then
		print(("[WARNING]: %s is already imported!"):format(name))
	end
	_parent.imports[name]=source
	return source
end

function eztask.depend(_parent,name)
	assert(_parent.imports[name]~=nil,"Missing dependency: "..name)
	return _parent.imports[name]
end

------------------------------[Signal Class]------------------------------
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
		if callback.parent_thread~=nil then
			callback.parent_thread.callbacks[callback]=nil
		end
		eztask.callbacks[callback]=nil
	end
	_signal.callbacks[callback.index]=callback
	if not no_thread then
		local current_thread=eztask.threads[running()] or eztask
		callback.parent_thread=current_thread
		current_thread.callbacks[callback]=callback
	end
	eztask.callbacks[callback]=callback
	return callback
end

function signal.invoke(_signal,...)
	for _,callback in pairs(_signal.callbacks) do
		if callback.parent_thread then
			local args={...}
			thread.new(function()
				callback.call(unpack(args))
			end,callback.parent_thread)()
		else
			callback.call(...)
		end
	end
end

function signal.detach(_signal)
	for _,callback in pairs(_signal.callbacks) do
		if callback.parent_thread then
			callback.parent_thread.callbacks[callback]=nil
		end
		eztask.callbacks[callback]=nil
	end
	_signal.callbacks={}
end

------------------------------[Property Class]------------------------------
property.__index=function(_property,k)
	if k=="value" then
		return rawget(_property,"_value")
	end
	return signal[k]
end
property.__newindex=function(_property,k,v)
	assert(k=="value",("Cannot assign %s to property"):format(k))
	local old=rawget(_property,"_value")
	if v~=old then
		rawset(_property,"_value",v)
		_property:invoke(v,old)
	end
end

function property.new(value)
	return setmetatable({callbacks={},_value=value},property)
end

------------------------------[Thread Class]------------------------------
thread.__index=thread

thread.import = eztask.import
thread.depend = eztask.depend

thread.__call=function(_thread,...)
	if _thread.coroutine~=nil then
		_thread:kill()
	end
	_thread.killed.value=false
	_thread.running.value=true
	_thread.resume_state=true
	_thread.coroutine=create(_thread.env)
	_thread.parent_thread.threads[_thread.coroutine]=_thread
	eztask.threads[_thread.coroutine]=_thread
	setmetatable(_thread.imports,{__index=(_thread.parent_thread or eztask).imports})
	_thread:resume(0,...)
	return _thread
end

function thread.new(env,parent_thread)
	if type(env)~="function" then env=eztask.require(env) or env end
	assert(type(env)=="function","Cannot create thread with invalid environment")
	
	local _thread={
		running       = property.new(false);
		killed        = property.new(false);
		resume_state  = false;
		tick          = 0;
		resume_tick   = 0;
		usage         = 0;
		parent_thread = parent_thread or eztask.threads[running()] or eztask;
		env           = env;
		threads       = {};
		callbacks     = {};
		imports       = {};
	}
	
	_thread.running:attach(function(state)
		if state==true then
			for _,sub_thread in pairs(_thread.threads) do
				sub_thread.running.value=sub_thread.resume_state
			end
		else
			for _,sub_thread in pairs(_thread.threads) do
				sub_thread.resume_state=sub_thread.running.value
				sub_thread.running.value=false
			end
		end
	end,true)
	
	return setmetatable(_thread,thread)
end

function thread.sleep(_thread,d)
	local real_tick=eztask.tick()
	local current_thread=eztask.threads[running()]
	if d==nil or type(d)=="number" then
		current_thread.resume_tick=current_thread.tick+(d or 0)
	elseif type(d)=="table" and (getmetatable(d)==signal or getmetatable(d)==property) then
		local bind
		bind=d:attach(function()
			bind:detach()
			current_thread.resume_tick=current_thread.tick
			current_thread:resume()
		end,true)
	else
		error("Cannot yield thread with "..type(d))
	end
	yield()
	return eztask.tick()-real_tick
end

function thread.resume(_thread,dt,...)
	if status(_thread.coroutine)=="dead" then
		if next(_thread.callbacks)==nil and next(_thread.threads)==nil then
			_thread:kill()
			return
		end
	end
	if _thread.running.value==true then
		dt=dt or 0
		local real_tick=eztask.tick()
		_thread.tick=_thread.tick+dt
		if status(_thread.coroutine)=="suspended" and _thread.resume_tick and _thread.resume_tick<=_thread.tick then
			_thread.resume_tick=nil
			local success,err=resume(_thread.coroutine,eztask._scope,...)
			if not success then
				print("[ERROR]: "..traceback(_thread.coroutine,err,1))
			end
		end
		for _,sub_thread in pairs(_thread.threads) do
			sub_thread:resume(dt)
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
	_thread.imports={}
	_thread.parent_thread.threads[_thread.coroutine]=nil
	eztask.threads[_thread.coroutine]=nil
	_thread.coroutine=nil
	_thread.killed.value=true
end

function eztask:step(dt)
	for _,_thread in pairs(eztask.threads) do
		if _thread.parent_thread==eztask then
			_thread:resume(dt)
		end
	end
end

eztask.signal   = signal
eztask.property = property
eztask.thread   = thread

return eztask