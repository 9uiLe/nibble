local dependencies = {}

function dependencies.github(project, tag, options)
    local name = string.gsub(project .. '_' .. tag, '/', '_')
    local path = os.getenv('DEPENDENCIES') .. '/' .. name
    assert(os.isdir(path), 'Unpinned Rive dependency: ' .. name)
    assert(options == nil or options.patches == nil,
        'Dependency patches must be part of the locked build inputs')
    return path
end

return dependencies
