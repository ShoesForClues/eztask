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
	_version = {2,0,6};
	imports  = {};
	threads  = {};
}

eztask.imports.eztask=eztask --wtf

--[Native Functions]
local unpack = unpack or table.unpack
local create = coroutine.create
local resume = coroutine.resume
local yield  = coroutine.yield
local status = coroutine.status
local wrap   = coroutine.wrap

--[Wrapped Functions]
eztask.assert  = assert
eztask.error   = error
eztask.require = require
eztask.tick    = os.clock

local _thread=setmetatable({},{
	__index=function(t,k)
		return eztask.current_thread[k] or eztask.current_thread.imports[k]
	end;
	__newindex=eztask.current_thread
})

function _thread:import(source,name)
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
	if type(source)=="function" then --Assuming it's already sandboxed
		source=source(_thread)
	end
	_thread.imports[name]=source
	return source
end

function _thread:depend(name)
	eztask.assert(_thread.imports[name]~=nil,"Missing dependency: "..name)
end

function eztask.new_signal()
	local signal={callbacks={}}
	
	function signal:attach(call,no_thread)
		eztask.assert(type(call)=="function",("Cannot attach %s to callback."):format(type(call)))
		local callback={call=call}
		function callback:detach()
			self.callbacks[self]=nil
			if self.parent_thread~=nil then
				self.parent_thread.callbacks[self]=nil
			end
		end
		self.callbacks[callback]=callback
		if not no_thread and eztask.current_thread then
			callback.parent_thread=eztask.current_thread
			eztask.current_thread.callbacks[callback]=callback
		end
		return callback
	end
	
	function signal:invoke(...)
		for _,callback in pairs(self.callbacks) do
			if callback.parent_thread then
				local args={...}
				callback.parent_thread.new_thread(function()
					callback.call(unpack(args))
				end):init()
			else
				callback.call(...)
			end
		end
	end
	
	return signal
end

function eztask.new_property(value)
	local property=eztask.new_signal()
	local _value,old_value=value
	
	property.__index=function(t,k)
		if k=="value" then
			return _value
		end
	end;
	property.__newindex=function(t,k,v)
		if k=="value" and _value~=v then
			old_value=_value;_value=v
			property:invoke(v,old_value)
		end
	end
	
	setmetatable(property,property)
	
	return property
end

function eztask.new_thread(env,parent_thread)
	if type(env)=="string" then env=eztask.require(env) or env end
	eztask.assert(type(env)=="function","Cannot create thread with invalid environment")
	
	local thread={
		running       = eztask.new_property(false,true);
		killed        = eztask.new_signal(true);
		tick          = 0;
		resume_tick   = 0;
		resume_state  = false;
		parent_thread = parent_thread or eztask;
		env           = env;
		threads       = {};
		callbacks     = {};
		imports       = {};
	}
	
	setmetatable(thread.imports,{__index=(thread.parent_thread or eztask).imports})
	
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
	
	function thread:resume(dt,...)
		thread.tick=thread.tick+(dt or 0)
		if thread.coroutine~=nil and status(thread.coroutine)=="dead" then
			thread:delete()
		elseif thread.coroutine~=nil and thread.running.value==true and status(thread.coroutine)=="suspended" and thread.resume_tick<=thread.tick then
			local previous_thread=eztask.current_thread
			eztask.current_thread=thread
			for _,sub_thread in pairs(thread.threads) do
				sub_thread:resume(dt)
			end
			eztask.assert(resume(thread.coroutine,_thread,...))
			eztask.current_thread=previous_thread
		end
	end
	
	function thread:sleep(d)
		local raw_tick=eztask.tick() or 0
		thread.resume_tick=thread.tick+(d or 0)
		yield()
		return eztask.tick()-raw_tick
	end
	
	function thread:delete()
		thread.running.value=false
		for _,child_thread in pairs(thread.threads) do
			child_thread:delete()
		end
		for _,callback in pairs(thread.callbacks) do
			callback:detach()
		end
		thread.coroutine=nil
		thread.parent_thread.threads[thread]=nil
		thread.killed:invoke()
	end
	
	function thread:init(...)
		if thread.coroutine~=nil then
			thread:delete()
		end
		thread.running.value=true
		thread.resume_state=true
		thread.coroutine=create(thread.env)
		thread.parent_thread.threads[thread]=thread
		if eztask.thread_init~=nil then
			eztask.thread_init(thread)
		end
		thread:resume(0,...)
		return thread
	end
	
	function thread.new_thread(env)
		return eztask.new_thread(env,thread)
	end
	
	return thread
end

function eztask:step(dt)
	for _,thread in pairs(eztask.threads) do
		thread:resume(dt)
	end
end
	
return eztask