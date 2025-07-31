local M = {}

local function read_bytes(file, count)
	return file:read(count)
end

local function read_uint32_le(file)
	local bytes = read_bytes(file, 4)
	if not bytes or #bytes < 4 then return nil end
	local value = 0
	for i = 1, 4 do
		value = value + (string.byte(bytes, i) << ((i - 1) * 8))
	end
	return value
end

local function read_int32_le(file)
	local val = read_uint32_le(file)
	if val == nil then return nil end
	if val >= 0x80000000 then
		val = val - 0x100000000
	end
	return val
end

local function read_uint16_le(file)
	local bytes = read_bytes(file, 2)
	if not bytes or #bytes < 2 then return nil end
	local value = (string.byte(bytes, 1) << 0) + (string.byte(bytes, 2) << 8)
	return value
end

local function read_uint8(file)
	local byte = read_bytes(file, 1)
	if not byte then return nil end
	return string.byte(byte)
end

local function print(job, s)
	ya.preview_widget(job, ui.Text.parse(s):area(job.area):wrap(ui.Wrap.YES))
end

local function rpad(s, len, char)
	return #s >= len and s or (s .. string.rep(char or ' ', len - #s))
end

function M:peek(job)
	local filepath = tostring(job.file.url)
	local file     = io.open(filepath, "rb")
	if not file then
		return print(job, "Error: Could not open file " .. filepath)
	end

	local ktx = {}

	local identifier          = read_bytes(file, 12)
	local expected_identifier = "\xAB\x4B\x54\x58\x20\x31\x31\xBB\x0D\x0A\x1A\x0A"
	if identifier ~= expected_identifier then
		file:close()
		return print(job, "Error: Invalid KTX file identifier.")
	end

	ktx.endianness            = read_uint32_le(file)
	ktx.glType                = read_uint32_le(file)
	ktx.glTypeSize            = read_uint32_le(file)
	ktx.glFormat              = read_uint32_le(file)
	ktx.glInternalFormat      = read_uint32_le(file)
	ktx.glBaseInternalFormat  = read_uint32_le(file)
	ktx.pixelWidth            = read_uint32_le(file)
	ktx.pixelHeight           = read_uint32_le(file)
	ktx.pixelDepth            = read_uint32_le(file)
	ktx.numberOfArrayElements = read_uint32_le(file)
	ktx.numberOfFaces         = read_uint32_le(file)
	ktx.numberOfMipmapLevels  = read_uint32_le(file)
	ktx.bytesOfKeyValueData   = read_uint32_le(file)

	ktx.keyValueData	= {}
	if ktx.bytesOfKeyValueData > 0 then
		local bytes_read_kv = 0
		while bytes_read_kv < ktx.bytesOfKeyValueData do
			local keyAndValueByteSize = read_uint32_le(file)
			if not keyAndValueByteSize then break end
			local key_value_pair_data = read_bytes(file, keyAndValueByteSize)
			if not key_value_pair_data then break end

			local null_pos = string.find(key_value_pair_data, "\0")
			if null_pos then
				local key   = string.sub(key_value_pair_data, 1, null_pos - 1)
				local value = string.sub(key_value_pair_data, null_pos + 1)
				ktx.keyValueData[key] = value
			end

			-- Pad to 4-byte boundary
			local padding = (4 - (keyAndValueByteSize % 4)) % 4
			if padding > 0 then
				read_bytes(file, padding)
			end
			bytes_read_kv = bytes_read_kv + keyAndValueByteSize + padding
		end
	end

	local v = {}
	v[#v+1] = '--------------------  header   --------------------'
	for key, value in pairs(ktx) do
		if key ~= 'keyValueData' then
			v[#v+1] = rpad(tostring(key), 30) .. rpad(tostring(value), 12) .. string.format("0x%x", value)
		end
	end
	v[#v+1] = ''
	v[#v+1] = '-------------------- meta data --------------------'
	for key, value in pairs(ktx.keyValueData) do
		v[#v+1] = rpad(tostring(key), 30) .. tostring(value)
	end
	return print(job, table.concat(v, '\n'))
end

function M:seek(job) require("code"):seek(job) end

return M
