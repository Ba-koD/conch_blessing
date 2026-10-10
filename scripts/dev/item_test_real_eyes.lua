-- Real uses of the installed provider establish the prediction/answer contract.
-- This is separate from the fast, reversible inventory matrix.
local S = require("scripts.dev.item_scenarios")
local H = require("scripts.dev.item_test_support")

S.add("REAL_EYES", "prediction", { conditions = true }, function(plan, id)
    plan.require("Magic Conch preview and activation APIs available", function()
        local api = MagicConch and MagicConch.API
        return api and type(api.PreviewResult) == "function" and type(api.TriggerMagicConch) == "function"
            and type(api.GetLastResult) == "function" and type(api.GetState) == "function"
            and type(MagicConch.GetCurrentRoomUsage) == "function" or nil,
            "requires Magic Conch's read-only PreviewResult API"
    end)
    plan.act(function(player, ctx)
        local config = MagicConch.Config
        local saved = { enabled = config.enabled, forcedReply = config.forcedReply,
            attemptsPerRoom = config.attemptsPerRoom, timing = config.timing, language = config.language }
        ctx.cleanupFns = ctx.cleanupFns or {}
        ctx.cleanupFns[#ctx.cleanupFns + 1] = function()
            for key, value in pairs(saved) do config[key] = value end
        end
        config.enabled, config.attemptsPerRoom = true, 0
        -- Shorten only the provider's presentation through its supported config;
        -- do not call the result callback or change its room-use/RNG ledger.
        config.timing = { shake = 1, wait = 1, display = 1, cooldown = 0 }
        player:AddCollectible(id, 0, false)
    end)
    for _, mode in ipairs({ "Positive", "Neutral", "Negative", "None" }) do
        plan.section("REAL_EYES / next answer with " .. mode)
        plan.waitUntil(function() return MagicConch.API.GetState() == "idle" end, 300, "provider idle")
        plan.wait(12)
        plan.act(function(_, ctx)
            MagicConch.Config.forcedReply = mode
            ctx.prediction = assert(ConchBlessing.realeyes.getPrediction())
            ctx.usage = MagicConch:GetCurrentRoomUsage()
        end)
        plan.check("repeated display reads do not consume a use or change the answer", function(_, ctx)
            for _ = 1, 100 do
                local answer = ConchBlessing.realeyes.getPrediction()
                if not answer or answer.id ~= ctx.prediction.id or answer.text ~= ctx.prediction.text
                    or answer.type ~= ctx.prediction.type then return false, "prediction changed before use" end
            end
            return H.expect(MagicConch:GetCurrentRoomUsage(), ctx.usage)
        end)
        plan.act(function(_, ctx)
            ctx.trigger = MagicConch.API.TriggerMagicConch("ConchBlessing Real Eyes test")
        end)
        plan.require("canonical Magic Conch activation accepted", function(_, ctx)
            return ctx.trigger and ctx.trigger.success == true, tostring(ctx.trigger and ctx.trigger.reason)
        end)
        plan.check("predicted text and type match the actual pending answer", function(_, ctx)
            local actual = ctx.trigger.pendingResult
            return actual.text == ctx.prediction.text and actual.type == ctx.prediction.type,
                "expected=" .. ctx.prediction.type .. ":" .. ctx.prediction.text
                    .. " actual=" .. tostring(actual.type) .. ":" .. tostring(actual.text)
        end)
        plan.waitUntil(function() return MagicConch.API.GetState() == "idle" end, 300, "real result resolved")
        plan.check("completed result matches the prediction and advances exactly one use", function(_, ctx)
            local actual = MagicConch.API.GetLastResult()
            local nextAnswer = ConchBlessing.realeyes.getPrediction()
            return actual and actual.text == ctx.prediction.text and actual.type == ctx.prediction.type
                and MagicConch:GetCurrentRoomUsage() == ctx.usage + 1
                and nextAnswer and nextAnswer.useNumber == ctx.prediction.useNumber + 1,
                "completed=" .. tostring(actual and actual.text) .. " usage=" .. MagicConch:GetCurrentRoomUsage()
        end)
    end
    plan.act(function() MagicConch.Config.enabled = false end)
    plan.check("disabled Conch hides the prediction", function()
        local answer, reason = ConchBlessing.realeyes.getPrediction()
        return answer == nil and reason == "DISABLED", "reason=" .. tostring(reason)
    end)
    plan.act(function(player)
        MagicConch.Config.enabled = true
        player:RemoveCollectible(id)
    end)
    plan.check("removal immediately withdraws prediction", function()
        local answer, reason = ConchBlessing.realeyes.getPrediction()
        return answer == nil and reason == "NO_OWNER", "reason=" .. tostring(reason)
    end)
    plan.section("REAL_EYES / visual and persistence checks",
        "Prediction label and eye icon belong above Magic Conch's result; visual placement and real Continue need manual verification")
end)

return S
