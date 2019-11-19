--[[
EZTask written by ShoesForClues Copyright (c) 2018-2019
	
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

local eztask={
	_version = {2,0,8};
	imports  = {};
	threads  = {};
	step_frequency = 1/60;
}

eztask.imports.eztask=eztask --wtf
eztask._scope=setmetatable({},{
	__index=function(_,k)
		return eztask.current_thread[k] or eztask.current_thread.imports[k]
	end
})

--Native Functions
local remove = table.remove
local unpack = unpack or table.unpack
local create = coroutine.create
local resume = coroutine.resume
local yield  = coroutine.yield
local status = coroutine.status
local wrap   = coroutine.wrap

--Wrapped Functions
eztask.assert  = assert
eztask.error   = error
eztask.require = require
eztask.tick    = os.clock

--Object types
local _thread   = {}
local _signal   = {}
local _property = {}

_thread.__index=_thread
_signal.__index=_signal
_property.__index=function(t,k)
	if k=="value" then
		return rawget(t,"_value")
	end
	return _signal[k]
end
_property.__newindex=function(t,k,v)
	eztask.assert(k=="value",("Cannot assign %s to property"):format(k))
	local old=rawget(t,"_value")
	if v~=old then
		rawset(t,"_value",v)
		t:invoke(v,old)
	end
end

function _thread.import(instance,source,name,not_sandboxed)
	eztask.assert(source~=nil,"Cannot import from nil")
	if name==nil then
		if type(source)=="string" then
			name=source:sub((source:match("^.*()/") or 0)+1,#source)
		else
			eztask.error("Cannot import "..type(source).." without a name")
		end
	else
		name=tostring(name)
	end
	local did_require,return_source=pcall(eztask.require,source)
	if did_require then
		source=return_source
	end
	if type(source)=="function" and not not_sandboxed then
		source=source(eztask._scope)
	end
	instance.imports[name]=source
	return source
end

function _thread.depend(instance,name)
	eztask.assert(instance.imports[name]~=nil,"Missing dependency: "..name)
end

function _thread.sleep(instance,d)
	local raw_tick=eztask.tick() or 0
	d=d or 0
	if type(d)=="number" then
		eztask.current_thread.resume_tick=eztask.current_thread.tick+d
	elseif type(d)=="table" and (getmetatable(d)==_signal or getmetatable(d)==_property) then
		local current_thread,bind=eztask.current_thread
		current_thread.resume_tick=math.huge
		bind=d:attach(function()
			bind:detach()
			current_thread.resume_tick=current_thread.tick
			current_thread:resume()
		end,true)
	else
		eztask.error("Cannot yield thread with "..type(d))
	end
	yield()
	return eztask.tick()-raw_tick
end

function _thread.yield(instance)
	local current_thread=eztask.current_thread
	if eztask.tick()-current_thread.raw_tick>=eztask.step_frequency/(#current_thread.parent_thread.threads-#current_thread.parent_thread.threads*current_thread.usage/2) then
		return current_thread:sleep(0)
	end
	return 0
end

function _thread.resume(instance,dt,...)
	instance.tick=instance.tick+(dt or 0)
	instance.raw_tick=eztask.tick()
	if instance.coroutine==nil or status(instance.coroutine)=="dead" then
		instance:delete()
	elseif instance.running.value==true and instance.resume_tick<=instance.tick then
		local previous_thread=eztask.current_thread
		eztask.current_thread=instance
		for _,sub_thread in pairs(instance.threads) do
			sub_thread:resume(dt)
		end
		eztask.assert(resume(instance.coroutine,eztask._scope,...))
		instance.usage=(eztask.tick()-instance.raw_tick)/eztask.step_frequency
		eztask.current_thread=previous_thread
	end
end

function _thread.delete(instance)
	instance.running.value=false
	for _,child_thread in pairs(instance.threads) do
		child_thread:delete()
	end
	for _,callback in pairs(instance.callbacks) do
		callback:detach()
	end
	remove(instance.parent_thread.threads,instance.pid)
	instance.imports={}
	instance.coroutine=nil
	instance.parent_thread.threads[instance]=nil
	instance.killed:invoke()
end

function _thread.init(instance,...)
	if instance.coroutine~=nil then
		instance:delete()
	end
	instance.running.value=true
	instance.resume_state=true
	instance.coroutine=create(instance.env)
	instance.pid=#instance.parent_thread.threads+1
	instance.parent_thread.threads[instance.pid]=instance
	if eztask.thread_init~=nil then
		eztask.thread_init(instance)
	end
	instance:resume(0,...)
	return thread
end

function _signal.attach(instance,call,no_thread)
	eztask.assert(type(call)=="function",("Cannot attach %s to callback."):format(type(call)))
	local callback={call=call}
	function callback:detach()
		instance.callbacks[self]=nil
		if self.parent_thread~=nil then
			self.parent_thread.callbacks[self]=nil
		end
	end
	instance.callbacks[callback]=callback
	if not no_thread and eztask.current_thread then
		callback.parent_thread=eztask.current_thread
		eztask.current_thread.callbacks[callback]=callback
	end
	return callback
end

function _signal.invoke(instance,...)
	for _,callback in pairs(instance.callbacks) do
		if callback.parent_thread then
			local args={...}
			eztask.new_thread(function()
				callback.call(unpack(args))
			end,callback.parent_thread):init()
		else
			callback.call(...)
		end
	end
end

function _thread.new_thread(env)
	return eztask.new_thread(env,eztask.current_thread)
end

function eztask.new_signal()
	return setmetatable({callbacks={}},_signal)
end

function eztask.new_property(value)	
	return setmetatable({callbacks={},_value=value},_property)
end

function eztask.new_thread(env,parent_thread)
	if type(env)=="string" then env=eztask.require(env) or env end
	eztask.assert(type(env)=="function","Cannot create thread with invalid environment")
	
	local thread={
		running       = eztask.new_property(false);
		killed        = eztask.new_signal();
		pid           = 0;
		tick          = 0;
		raw_tick      = 0;
		resume_tick   = 0;
		usage         = 0;
		resume_state  = false;
		parent_thread = parent_thread or eztask;
		env           = env;
		threads       = {};
		callbacks     = {};
		imports       = {};
	}
	
	thread.running:attach(function(state)
		if state==true then
			for _,sub_thread in pairs(thread.threads) do
				sub_thread.running.value=sub_thread.resume_state
			end
		else
			for _,sub_thread in pairs(thread.threads) do
				sub_thread.resume_state=sub_thread.running.value
				sub_thread.running.value=false
			end
		end
	end,true)
	
	setmetatable(thread.imports,{__index=(thread.parent_thread or eztask).imports})
	setmetatable(thread,_thread)
	
	return thread
end

function eztask:step(dt)
	for _,thread in pairs(eztask.threads) do
		thread:resume(dt)
	end
end
	
return eztask