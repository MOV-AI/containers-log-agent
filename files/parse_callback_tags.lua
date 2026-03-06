-- Lua filter to extract specific tags from callback_logs format
-- Optimized for minimal CPU operations per log line
-- Targets: ui (True|False), node (any string value)
-- Also strips ANSI codes if present in log field

function parse_callback_tags(tag, timestamp, record)
    local tags_str = record["tags"]

    if tags_str then
        -- Direct extraction of ui tag (True or False only)
        -- Avoids looping through all tags
        local ui_match = string.match(tags_str, "ui%s*:%s*(True|False)")
        if ui_match then
            record["ui"] = ui_match
            record["has_ui"] = true
        end

        -- Direct extraction of node tag (any value up to pipe separator or end)
        -- Trims trailing whitespace in one operation
        local node_raw = string.match(tags_str, "node%s*:%s*([^|]+)")
        if node_raw then
            record["node"] = string.match(node_raw, "^(.-)%s*$") or node_raw
            record["has_node"] = true
        end
    end

    -- Strip ANSI codes only if escape sequences are present in log
    -- Avoids regex operations on logs without ANSI codes
    local log_field = record["log"]
    if log_field and string.find(log_field, "\27") then
        -- Single pass removes ESC [ sequences commonly used for colors, bold, etc.
        record["log"] = string.gsub(log_field, "\27%[[0-9;]*[mGKHJABCDEFPsu]", "")
    end

    return 1, timestamp, record
end
