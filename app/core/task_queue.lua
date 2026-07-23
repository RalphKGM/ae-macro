local TaskQueue = {}
TaskQueue.__index = TaskQueue

function TaskQueue.new(tasks, checkpoint)
  local self = setmetatable({}, TaskQueue)
  self.tasks = tasks or {}
  self.index = (checkpoint and checkpoint.task_index) or 1
  self.repetition = (checkpoint and checkpoint.repetition) or 0
  return self
end

function TaskQueue:current()
  local guard = 0
  while self.index <= #self.tasks and guard <= #self.tasks do
    local task = self.tasks[self.index]
    if task and task.enabled ~= false then return task end
    self.index = self.index + 1
    self.repetition = 0
    guard = guard + 1
  end
  return nil
end

function TaskQueue:recordSuccess()
  local task = self:current()
  if not task then return nil end
  self.repetition = self.repetition + 1
  if not task.infinite and self.repetition >= (task.repetitions or 1) then
    self.index = self.index + 1
    self.repetition = 0
  end
  return self:current()
end

function TaskQueue:skip()
  self.index = self.index + 1
  self.repetition = 0
  return self:current()
end

function TaskQueue:restart()
  self.index = 1
  self.repetition = 0
  return self:current()
end

function TaskQueue:snapshot()
  return { task_index = self.index, repetition = self.repetition }
end

return TaskQueue
