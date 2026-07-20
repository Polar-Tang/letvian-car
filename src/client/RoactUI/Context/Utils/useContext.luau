local Roact = require(game.ReplicatedStorage.Shared.Roact)

return function(contextMap)
	local keys = {}
	local contexts = {}

	for key, ctx in pairs(contextMap) do
		table.insert(keys, key)
		table.insert(contexts, ctx)
	end

	return function(renderFn)
		local function wrap(i, collected)
			local ctx = contexts[i]

			if not ctx then
				return renderFn(collected)
			end
			local key = keys[i]
			return Roact.createElement(ctx.Consumer, {
				render = function(value)
					local nextCollected = table.clone(collected)
					nextCollected[key] = value

					return wrap(i + 1, nextCollected)
				end,
			})
		end

		return wrap(1, {})
	end
end
