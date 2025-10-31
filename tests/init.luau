local Maid = require("./src/maid")
assert(type(Maid) == "table", "Library does not return a table")

assert(Maid.new(), ".new() does not create a maid")
assert(Maid.is(Maid.new()), ".is() does not return true for Maid objects")
assert(not Maid.is("test"), ".is() does not return false for non-Maid object")

local function getTracker()
	local data = {
		timesCleaned = 0,
	}

	function data:Destroy()
		data.timesCleaned += 1
	end

	return data
end

local maid = Maid.new()

local called = false
maid:Add(function()
	called = true
end)

local tracker = getTracker()
maid.value = tracker
assert(maid.value == tracker, "__index function does retrieve tasks")

local newValue = newproxy()
maid.value = newValue
assert(maid.value == newValue, "__newindex function does not update tasks")
assert(tracker.timesCleaned == 1, "__newindex does not clean old tasks")

assert(maid:Add(tracker) == tracker, ":Add() does not return the task")
maid:Add(tracker)

maid:DoCleaning()
assert(not next(maid._tasks), "maid._tasks was not empty after calling :DoCleaning()")
assert(called, ":DoCleaning() did not call cleanup function")
assert(tracker.timesCleaned == 3, ":DoCleaning() can't call the same task twice")
