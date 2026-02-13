-- Pass through container metadata from Docker log driver
-- The fluentd log driver already provides:
-- - container_name: friendly container name
-- - container_id: full container ID
-- - image_name: docker image name
-- We just pass these through to Loki
function extract_container_name(tag, timestamp, record)
    -- Container name is already provided by Docker's fluentd log driver
    -- No transformation needed - just pass through
    return 2, timestamp, record
end
