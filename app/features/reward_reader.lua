local RewardReader = {}
RewardReader.__index = RewardReader

function RewardReader.new(options)
  return setmetatable({
    vision = options.vision,
    logger = options.logger,
  }, RewardReader)
end

function RewardReader:read(imagePath, callback)
  if not imagePath then callback({ items = {}, summary = "no result screenshot" }) return end
  local id, err = self.vision:request("read_rewards", {
    image_path = imagePath,
  }, function(result, readError)
    if not result then
      self.logger:warn("reward_read_failed", { error = readError })
      callback({ items = {}, summary = "rewards unreadable" }, readError)
      return
    end
    self.logger:info("rewards_read", {
      summary = result.summary,
      count = #(result.items or {}),
    })
    callback(result)
  end)
  if not id then
    self.logger:warn("reward_request_failed", { error = err })
    callback({ items = {}, summary = "rewards unreadable" }, err)
  end
end

return RewardReader
