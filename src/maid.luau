-- stylua: ignore
local defer = 
	if _G.RUNTIME == "lune" then
		require("@lune/task").defer
	elseif _G.RUNTIME == "roblox" then
		task.defer
	else
		nil

-- stylua: ignore
local cancel = 
	if _G.RUNTIME == "lune" then
		require("@lune/task").cancel
	elseif _G.RUNTIME == "roblox" then
		task.cancel
	else
		coroutine.close

--[=[
	Check [Maid.clean] to see how different types of tasks get cleaned up.

	@within Maid
	@type Task any
]=]
export type Task = any

--[=[
	@class Maid

	A class containing a list of tasks to be cleaned up at a later point.
]=]
local Maid = {} :: impl

type self = {
	_tasks: { [any]: Task? },

	[any]: any, -- Typehack to make maid objects not read-only
}
type impl = {
	is: (value: Maid | any) -> boolean,
	new: () -> Maid,

	__index: (self: Maid, key: string) -> any | Task,
	__newindex: (self: Maid, key: string, newTask: Task | nil) -> (),

	Add: <T>(self: Maid, task: T) -> T,
	GiveTask: (self: Maid, task: Task) -> number,

	clean: (task: Task) -> (),

	DoCleaning: (self: Maid) -> (),
	Destroy: (self: Maid) -> (),
}

export type Maid = typeof(setmetatable(
	{} :: self,
	{} :: {
		-- Typehack to get library members to work with the __index function
		__index: typeof(setmetatable(Maid, {} :: { __index: () -> Task? })),
	}
))

--[=[
	Returns true if the given value is a [Maid].
]=]
function Maid.is(value: Maid | any): boolean
	return type(value) == "table" and getmetatable(value :: any) == Maid
end

--[=[
	Creates a new [Maid].
]=]
function Maid.new(): Maid
	--[=[
		The list of tasks this maid is tracking.

		@within Maid
		@prop _tasks { [any]: Task? }
		@private
	]=]

	local self = setmetatable({
		_tasks = {},
	}, Maid)

	return self :: any
end

--[=[
	Returns a member of the [Maid] library, or if it doesn't exist a task with the given key.

	```lua
	local maid = Maid.new()
	maid.Car = Car.new()
	print(maid.Car) --> <car object>

	-- Meanwhile
	print(maid.clean) --> <Maid.clean function object>
	```
]=]
function Maid:__index(key: string): any | Task
	return Maid[key] or self._tasks[key]
end

--[=[
	Adds a new task with the given key.
	If an old task existed with the same key it will get cleaned up with [Maid.clean].
	If newTask is nil it will cleanup the existing task with the same key.

	```lua
	local maid = Maid.new()
	maid.Car = Car.new() -- Spawns a new car
	maid.Car = Car.new() -- Spawns a new car while destroying the old one
	maid.Car = nil -- Destroys the existing car
	```

	@error "Cannot use '{key}' as a task key" -- Is thrown when you try to add a task with the key being the same as a member of the [Maid] library.
]=]
function Maid:__newindex(key: string, newTask: Task | nil)
	if Maid[key] then
		error(`Cannot use '{key}' as a task key`, 2)
	end

	local tasks = self._tasks
	local oldTask = tasks[key]
	if oldTask == newTask then
		return
	end

	tasks[key] = newTask

	if oldTask ~= nil then
		Maid.clean(oldTask)
	end
end

--[=[
	Adds a new task to the maid and then returns the same task.

	```lua
	local maid = Maid.new()
	local car = maid:Add(Car.new())
	```

	@param task Task
	@return Task

	@error "Task cannot be nil" -- Is thrown when you call this function with the task being nil.
]=]
function Maid:Add<T>(task: T): T
	if task == nil then
		error("Task cannot be nil", 2)
	end

	self[#self._tasks + 1] = task

	return task
end

--[=[
	Adds a new task to the maid and returns its task key.

	```lua
	local maid = Maid.new()
	local taskId = maid:GiveTask(function()
		print("Cleaned!")
	end)

	-- Later...
	maid[taskId] = nil --> Cleaned!
	```

	@error "Task cannot be nil" -- Is thrown when you call this function with the task being nil.
]=]
function Maid:GiveTask(task: Task): number
	if task == nil then
		error("Task cannot be nil", 2)
	end

	local id = #self._tasks + 1
	self[id] = task

	return id
end

--[=[
	Performs / cleans the given task.

	| Task type				| Action upon cleaning									| Runtime	|
	|-----------------------|-------------------------------------------------------|-----------|
	| function				| Calls the function									|
	| thread				| Cancels the thread via task.cancel / couroutine.close	|
	| table					| Calls :Destroy() / :destroy() on it if it exists		|
	| Maid					| Calls :DoCleaning() on it								|
	| Instance				| Calls :Destroy() on it								| Roblox	|
	| RBXScriptConnection	| Calls :Disconnect() on it								| Roblox	|
]=]
function Maid.clean(task: Task)
	if type(task) == "function" then
		task()
	elseif type(task) == "thread" then
		local cancelled, reason
		if coroutine.running() ~= task then
			cancelled, reason = pcall(cancel, task)
		end

		if not cancelled and defer then
			(defer :: any)(cancel, task)
		elseif not cancelled then
			(warn or print)(
				debug.traceback(`[Maid] Unable to cancel thread {task}: {reason or "cannot cancel own thread"}`, 2) -- reason is only nil if coroutine.running() == task
			)
		end
	elseif _G.RUNTIME == "roblox" and typeof(task) == "Instance" then
		task:Destroy()
	elseif _G.RUNTIME == "roblox" and typeof(task) == "RBXScriptConnection" then
		task:Disconnect()
	elseif type(task) == "table" then
		if type(task.Destroy) == "function" then
			task:Destroy()
		elseif type(task.destroy) == "function" then
			task:destroy()
		end
	end
end

--[=[
	Calls [Maid.clean] on all tasks tracked by this maid, and then removes them as entries.

	This process will repeat until the task list is empty,
	meaning cleanup tasks can add new tasks while cleaning which will then also get cleaned up.

	```lua
	local maid = Maid.new()
	maid:Add(Car.new())
	maid:Add(signal:Connect(function() end)) -- Assuming it can be disconnected via :Destroy()
	maid:Add(function()
		print("Hi!")
	end)

	maid:DoCleaning() -- Destroys car, disconnects the connected signal, and prints "Hi!"
	```
]=]
function Maid:DoCleaning()
	local tasks = self._tasks
	local clean = Maid.clean

	local index, value = next(tasks)
	while value ~= nil do
		tasks[index] = nil
		clean(value)
		index, value = next(tasks)
	end
end

--[=[
	Alias for [Maid:DoCleaning].

	@within Maid
	@method Destroy
]=]
Maid.Destroy = Maid.DoCleaning

return Maid
