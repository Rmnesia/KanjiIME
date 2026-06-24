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

local function get_readings(env)
  if env.kanjiime_readings == nil then
    local file_name = env.engine.schema.config:get_string("kanjiime_reading_filter/readings")
    env.kanjiime_readings = load_readings(user_data_path(file_name or ""))
  end
  return env.kanjiime_readings
end

local function reading_text(comment)
  if not comment then
    return nil
  end
  local text = comment:match("^%((.*)%)$")
  return text or comment
end

local shifted_digit_index = {
  ["exclam"] = 0,
  ["at"] = 1,
  ["numbersign"] = 2,
  ["dollar"] = 3,
  ["percent"] = 4,
  ["asciicircum"] = 5,
  ["ampersand"] = 6,
  ["asterisk"] = 7,
  ["parenleft"] = 8,
  ["Shift+exclam"] = 0,
  ["Shift+at"] = 1,
  ["Shift+numbersign"] = 2,
  ["Shift+dollar"] = 3,
  ["Shift+percent"] = 4,
  ["Shift+asciicircum"] = 5,
  ["Shift+ampersand"] = 6,
  ["Shift+asterisk"] = 7,
  ["Shift+parenleft"] = 8,
  ["Shift+1"] = 0,
  ["Shift+2"] = 1,
  ["Shift+3"] = 2,
  ["Shift+4"] = 3,
  ["Shift+5"] = 4,
  ["Shift+6"] = 5,
  ["Shift+7"] = 6,
  ["Shift+8"] = 7,
  ["Shift+9"] = 8,
}

local function candidate_at(context, index)
  local composition = context.composition
  if not composition or composition:empty() then
    return nil
  end

  local segment = composition:back()
  if not segment then
    return nil
  end

  local menu = segment.menu
  if menu and menu.get_candidate_at then
    return menu:get_candidate_at(index)
  end
  if segment.get_candidate_at then
    return segment:get_candidate_at(index)
  end
  return nil
end

function kanjiime_reading_processor(key, env)
  local index = shifted_digit_index[key:repr()]
  if index == nil then
    return 2
  end

  local engine = env.engine
  local context = engine.context
  if not context:has_menu() then
    return 2
  end

  local cand = candidate_at(context, index)
  if not cand then
    return 2
  end

  local reading = reading_text(get_readings(env)[cand.text])
  if not reading or reading == "" then
    return 2
  end

  engine:commit_text(reading)
  context:clear()
  return 1
end

function kanjiime_reading_filter(input, env)
  local readings = get_readings(env)

  for cand in input:iter() do
    local reading = readings[cand.text]
    if reading then
      yield(ShadowCandidate(cand, cand.type, cand.text, reading))
    else
      yield(cand)
    end
  end
end
