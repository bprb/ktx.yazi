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

local function lpad(s, len, char)
	return #s >= len and s or ( string.rep(char or ' ', len - #s) .. s)
end


local function safe_ascii(str)
    local result = ""
    for i = 1, #str do
        local b = string.byte(str, i)
		if b ~= 0 then
        	if b < 32 or b > 255 then
				result = result .. string.format("\\x%02X", b)
        	else
        	    result = result .. string.sub(str, i, i)
        	end
		end
    end
    return result
end

local function getUint32(dataView, offset, isLittleEndian)
    local byte1 = string.byte(dataView, offset + 1)
    local byte2 = string.byte(dataView, offset + 2)
    local byte3 = string.byte(dataView, offset + 3)
    local byte4 = string.byte(dataView, offset + 4)

    if isLittleEndian then
        return byte1 + (byte2 * 256) + (byte3 * 65536) + (byte4 * 16777216)
    else
        return byte4 + (byte3 * 256) + (byte2 * 65536) + (byte1 * 16777216)
    end
end

function M:peek(job)
	local filepath = tostring(job.file.url)
	local file     = io.open(filepath, "rb")
	if not file then
		return print(job, "Error: Could not open file " .. filepath)
	end

	local dataView = file:read("*a")
	file:close()

    local offset = 0

	local expected_identifier = "\xAB\x4B\x54\x58\x20\x31\x31\xBB\x0D\x0A\x1A\x0A"
	local identifier          = string.sub(dataView, offset + 1, offset + 1 + #expected_identifier - 1)
	if identifier ~= expected_identifier then
		return print(job, "Error: Invalid KTX file identifier.")
	end
    offset = offset + 12

    local endiannessTest = getUint32(dataView, offset, true)
    local isLittleEndian = (endiannessTest == 0x04030201)
    local isBigEndian = (endiannessTest == 0x01020304)

    if not isLittleEndian and not isBigEndian then
        return print(job, "Invalid KTX endianness field.")
    end
    offset = offset + 4

    local header = {}
    header.glType                = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4
    header.glTypeSize            = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4
    header.glFormat              = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4
    header.glInternalFormat      = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4
    header.glBaseInternalFormat  = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4
    header.pixelWidth            = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4
    header.pixelHeight           = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4
    header.pixelDepth            = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4
    header.numberOfArrayElements = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4
    header.numberOfFaces         = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4
    header.numberOfMipmapLevels  = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4
    header.bytesOfKeyValueData   = getUint32(dataView, offset, isLittleEndian) ; offset = offset + 4

    if header.numberOfMipmapLevels == 0 then
        local maxDim = math.max(header.pixelWidth, header.pixelHeight, header.pixelDepth)
        header.numberOfMipmapLevels = math.floor(math.log(maxDim, 2)) + 1
    end

    local keyValueDataBytes = string.sub(dataView, offset + 1, offset + header.bytesOfKeyValueData)
    offset = offset + header.bytesOfKeyValueData

    local keyValuePairs = {}
    local kvOffset = 0
    while kvOffset < #keyValueDataBytes do
        local keyAndValueSize = getUint32(keyValueDataBytes, kvOffset, isLittleEndian)
        kvOffset = kvOffset + 4

        local keyAndValueBytes = string.sub(keyValueDataBytes, kvOffset + 1, kvOffset + keyAndValueSize)
        kvOffset = kvOffset + keyAndValueSize

        local keyEnd = 0
        while keyEnd < #keyAndValueBytes and string.byte(keyAndValueBytes, keyEnd + 1) ~= 0x00 do
            keyEnd = keyEnd + 1
        end
        local key = string.sub(keyAndValueBytes, 1, keyEnd)
        local value = string.sub(keyAndValueBytes, keyEnd + 2)

        keyValuePairs[key] = value

        local padding = (4 - (keyAndValueSize % 4)) % 4
        kvOffset = kvOffset + padding
    end

    local mipmapLevels = {}
    local currentPixelWidth  = header.pixelWidth
    local currentPixelHeight = header.pixelHeight
    local currentPixelDepth  = header.pixelDepth

    for level = 0, header.numberOfMipmapLevels - 1 do
        local imageSize = getUint32(dataView, offset, isLittleEndian)
        offset = offset + 4

        local imagePadding = (4 - (offset % 4)) % 4
        offset = offset + imagePadding

        table.insert(mipmapLevels, {
            level      = level,
            imageSize  = imageSize,
            width      = currentPixelWidth,
            height     = currentPixelHeight,
            depth      = currentPixelDepth,
            dataOffset = offset,
            dataLength = imageSize
        })

        offset = offset + imageSize

        currentPixelWidth  = math.max(1, math.floor(currentPixelWidth / 2))
        currentPixelHeight = math.max(1, math.floor(currentPixelHeight / 2))
        currentPixelDepth  = math.max(1, math.floor(currentPixelDepth / 2))
    end

	local sorted = {}
	for key in pairs(header) do table.insert(sorted, key) end
	table.sort(sorted)

	local v = {}

	v[#v+1] = '-------------------- header ----------------------------'
	for _, key in ipairs(sorted) do
		local value = header[key]
		v[#v+1] = rpad(tostring(key), 30) .. ' ' .. rpad(tostring(value), 12) .. ' ' .. string.format("0x%x", value)
	end
	v[#v+1] = ''

	v[#v+1] = '------------------- meta data --------------------------'
	sorted = {}
	for key in pairs(keyValuePairs) do table.insert(sorted, key) end
	table.sort(sorted)
	for _, key in ipairs(sorted) do
		local value = keyValuePairs[key]
		v[#v+1] = rpad(safe_ascii(key), 30) .. ' ' .. safe_ascii(value)
	end

	v[#v+1] = ''

	v[#v+1] = '------------------- mip levels -------------------------'
	v[#v+1] = '  mip width  height   depth   size            offset'
	for index, mip in ipairs(mipmapLevels) do
		v[#v+1] = lpad(tostring(index), 5) .. ' ' ..
				lpad(tostring(mip.width), 5) .. ' × ' .. 
				lpad(tostring(mip.height), 5) .. ' × ' ..
				mip.depth .. '      ' ..
				lpad(tostring(mip.dataLength), 7) .. ' bytes at ' ..
				string.format("0x%08x",mip.dataOffset)
	end

	return print(job, table.concat(v, '\n'))
end

function M:seek(job) require("code"):seek(job) end

return M
