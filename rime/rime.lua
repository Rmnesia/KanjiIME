local function load_readings(path)
  local readings = {}
  local file = io.open(path, "r")
  if not file then
    return readings
  end

  for line in file:lines() do
    local text, reading = line:match("^([^\t]+)\t(.+)$")
    if text and reading and readings[text] == nil then
      readings[text] = reading
    end
  end
  file:close()
  return readings
end

local function user_data_path(file_name)
  local sep = package.config:sub(1, 1)
  return rime_api.get_user_data_dir() .. sep .. file_name
end

function kanjiime_reading_filter(input, env)
  if env.kanjiime_readings == nil then
    local file_name = env.engine.schema.config:get_string("kanjiime_reading_filter/readings")
    env.kanjiime_readings = load_readings(user_data_path(file_name or ""))
  end

  for cand in input:iter() do
    local reading = env.kanjiime_readings[cand.text]
    if reading then
      yield(ShadowCandidate(cand, cand.type, cand.text, reading))
    else
      yield(cand)
    end
  end
end
