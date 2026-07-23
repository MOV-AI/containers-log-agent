--============================================================================
-- Lua Filter: parse_callback_tags
-- Purpose: Extract specific fields from callback logs and clean ANSI codes
-- Input: Record with parsed 'tags' field, or raw callback line in 'log'
-- Output: Enhanced record with extracted fields and cleaned log
--============================================================================
-- Extracted Fields:
--   ui (string): True|False, set only if ui tag present and valid
--   has_ui (bool): Flag indicating if ui tag exists with valid value
--   node (string): Any string value, trimmed, set only if node tag present
--   has_node (bool): Flag indicating if node tag exists
--   log (string): Original log field with ANSI escape sequences stripped
--
-- Tag Format Examples:
--   "ui:True|node:worker-01"           -> ui=True, node=worker-01, has_ui=true, has_node=true
--   "ui:False"                         -> ui=False, has_ui=true
--   "node:primary|ui:True|custom:data" -> ui=True, node=primary, has_ui=true, has_node=true
--   ""                                 -> no fields extracted
--
-- ANSI Code Removal:
--   Strips CSI sequences (colors, bold, cursor movement, etc.)
--   Only operates on logs containing ESC character (performance optimization)
--
-- Performance Notes:
--   - Tags extraction uses direct string matching (no loops)
--   - ANSI stripping is conditional (skips logs without escape sequences)
--   - Single-pass regex operations throughout
--============================================================================

local function resolve_tags_str(record)
    local tags_str = record["tags"]
    if tags_str and string.len(tags_str) > 0 then
        return tags_str
    end

    local log_field = record["log"]
    if type(log_field) ~= "string" then
        return nil
    end

    -- Fast-path fallback for pre-parser callback logs:
    -- [LEVEL][timestamp][module][function][lineno]: [tag:value|tag:value] message
    return string.match(log_field, "^%[[^%]]+%]%[[^%]]+%]%[[^%]]+%]%[[^%]]+%]%[[0-9]+%]:%s*%[([^%]]*)%]")
end

function parse_callback_tags(tag, timestamp, record)
    local tags_str = resolve_tags_str(record)

    -- Extract ui and node tags from pipe-separated tag list
    if tags_str and string.len(tags_str) > 0 then

        -- Extract ui tag and only accept canonical boolean spellings.
        local ui_raw = string.match(tags_str, "ui%s*:%s*([^|]+)")
        if ui_raw then
            local ui_match = string.match(ui_raw, "^%s*(.-)%s*$") or ui_raw
            if ui_match == "True" or ui_match == "False" then
                record["ui"] = ui_match
                record["has_ui"] = true
            end
        end

        -- Extract node tag: captures any value up to pipe separator or end of string
        -- Pattern: node : optional_whitespace (any_chars_except_pipe) optional_whitespace
        -- Trim trailing whitespace with second match
        local node_raw = string.match(tags_str, "node%s*:%s*([^|]+)")
        if node_raw then
            record["node"] = string.match(node_raw, "^(.-)%s*$") or node_raw
            record["has_node"] = true
        end
    end

    -- Strip ANSI escape sequences from log field
    -- Only performs this operation if ESC character (0x1B) is detected
    -- Prevents unnecessary regex operations on clean logs
    local log_field = record["log"]
    if log_field and type(log_field) == "string" and string.find(log_field, "\27") then
        -- Removes CSI sequences: ESC [ ... letter
        -- Covers: colors (m), cursor movement (H,J,K), erasing (K), mode setting (h,l),
        --         graphics rendition (SGR), and other standard ANSI codes
        record["log"] = string.gsub(log_field, "\27%[[0-9;]*[mGKHJABCDEFPsu]", "")
    end

    -- Return code 1 = continue processing, 0 = drop record
    -- timestamp = original timestamp from FluentBit
    -- record = enhanced with extracted and cleaned fields
    return 1, timestamp, record
end
