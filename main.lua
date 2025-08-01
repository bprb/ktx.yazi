local M = {}

local theme = THEME

local function error(job, s, color)
	ya.preview_widget(job, ui.Text.parse(s):area(job.area):wrap(ui.Wrap.YES):fg("red"))
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

local function as_u32(bytes, offset, isLittleEndian)
	local byte1 = string.byte(bytes, offset + 1)
	local byte2 = string.byte(bytes, offset + 2)
	local byte3 = string.byte(bytes, offset + 3)
	local byte4 = string.byte(bytes, offset + 4)

	if isLittleEndian then
		return byte1 + (byte2 * 256) + (byte3 * 65536) + (byte4 * 16777216)
	else
		return byte4 + (byte3 * 256) + (byte2 * 65536) + (byte1 * 16777216)
	end
end

local known_formats = {

	[0x1903] = 'GL_RED',
	[0x1904] = 'GL_GREEN',
	[0x1905] = 'GL_BLUE',
	[0x1906] = 'GL_ALPHA',
	[0x1907] = 'GL_RGB',
	[0x1908] = 'GL_RGBA',
	[0x1909] = 'GL_LUMINANCE',
	[0x190A] = 'GL_LUMINANCE_ALPHA',

	[0x190C] = 'GL_RED',
	[0x190D] = 'GL_RG',
	[0x190E] = 'GL_RGB',
	[0x190F] = 'GL_RGBA',
	[0x8051] = 'GL_RGB8',
	[0x8058] = 'GL_RGBA8',
	[0x8052] = 'GL_RGB10',
	[0x8059] = 'GL_RGBA10',

	[0x1902] = 'GL_DEPTH_COMPONENT',
	[0x1901] = 'GL_STENCIL_INDEX',
	[0x8D40] = 'GL_DEPTH_STENCIL',

	[0x83F0] = 'GL_COMPRESSED_RGB_S3TC_DXT1_EXT',
	[0x83F1] = 'GL_COMPRESSED_RGBA_S3TC_DXT1_EXT',
	[0x83F2] = 'GL_COMPRESSED_RGBA_S3TC_DXT3_EXT',
	[0x83F3] = 'GL_COMPRESSED_RGBA_S3TC_DXT5_EXT',

	[0x8D64] = 'GL_ETC1_RGB8_OES',

	[0x9274] = 'GL_COMPRESSED_RGB8_ETC2',
	[0x9275] = 'GL_COMPRESSED_RGB8_PUNCHTHROUGH_ALPHA1_ETC2',
	[0x9276] = 'GL_COMPRESSED_RGBA8_ETC2_EAC',
	[0x9277] = 'GL_COMPRESSED_R11_EAC',
	[0x9278] = 'GL_COMPRESSED_SIGNED_R11_EAC',
	[0x9279] = 'GL_COMPRESSED_RG11_EAC',
	[0x927A] = 'GL_COMPRESSED_SIGNED_RG11_EAC',

	[0x9300] = 'GL_COMPRESSED_RGBA_ASTC_4x4_KHR',
	[0x9301] = 'GL_COMPRESSED_RGBA_ASTC_5x4_KHR',
	[0x9302] = 'GL_COMPRESSED_RGBA_ASTC_5x5_KHR',

	[0x8C00] = 'GL_COMPRESSED_RGB_PVRTC_4BPPV1_IMG',
	[0x8C01] = 'GL_COMPRESSED_RGB_PVRTC_2BPPV1_IMG',
	[0x8C02] = 'GL_COMPRESSED_RGBA_PVRTC_4BPPV1_IMG',
	[0x8C03] = 'GL_COMPRESSED_RGBA_PVRTC_2BPPV1_IMG',

	[0x8229] = 'GL_R8',
	[0x822A] = 'GL_R16',
	[0x822B] = 'GL_RG8',
	[0x822C] = 'GL_RG16',
	[0x822D] = 'GL_R16F',
	[0x822E] = 'GL_R32F',
	[0x822F] = 'GL_RG16F',
	[0x8230] = 'GL_RG32F',
	[0x8231] = 'GL_R8I',
	[0x8232] = 'GL_R8UI',
	[0x8233] = 'GL_R16I',
	[0x8234] = 'GL_R16UI',
	[0x8235] = 'GL_R32I',
	[0x8236] = 'GL_R32UI',
	[0x8237] = 'GL_RG8I',
	[0x8238] = 'GL_RG8UI',
	[0x8239] = 'GL_RG16I',
	[0x823A] = 'GL_RG16UI',
	[0x823B] = 'GL_RG32I',
	[0x823C] = 'GL_RG32UI',
}

local known_types = {
	[0x1400] = 'GL_BYTE',
	[0x1401] = 'GL_UNSIGNED_BYTE',
	[0x1402] = 'GL_SHORT',
	[0x1403] = 'GL_UNSIGNED_SHORT',
	[0x1404] = 'GL_INT',
	[0x1405] = 'GL_UNSIGNED_INT',
	[0x1406] = 'GL_FLOAT',
	[0x140B] = 'GL_HALF_FLOAT',
	[0x140C] = 'GL_FIXED',

	[0x8033] = 'GL_UNSIGNED_SHORT_5_6_5',
	[0x8034] = 'GL_UNSIGNED_SHORT_4_4_4_4',
	[0x8035] = 'GL_UNSIGNED_SHORT_5_5_5_1',
}

function M:peek(job)
	local filepath = tostring(job.file.url)
	local file	 = io.open(filepath, "rb")
	if not file then
		return error(job, "Error: Could not open file " .. filepath)
	end

	local bytes = file:read("*a")
	file:close()

	local offset = 0

	local expected_identifier = "\xAB\x4B\x54\x58\x20\x31\x31\xBB\x0D\x0A\x1A\x0A"
	local identifier          = string.sub(bytes, offset + 1, offset + 1 + #expected_identifier - 1)
	if identifier ~= expected_identifier then
		return error(job, "Error: Invalid KTX file identifier.")
	end
	offset = offset + 12

	local endiannessTest = as_u32(bytes, offset, true)
	local isLittleEndian = (endiannessTest == 0x04030201)
	local isBigEndian	 = (endiannessTest == 0x01020304)

	if not isLittleEndian and not isBigEndian then
		return error(job, "Invalid KTX endianness field.")
	end
	offset = offset + 4

	local header = {}
	header.glType                = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4
	header.glTypeSize            = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4
	header.glFormat              = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4
	header.glInternalFormat      = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4
	header.glBaseInternalFormat  = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4
	header.pixelWidth            = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4
	header.pixelHeight           = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4
	header.pixelDepth            = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4
	header.numberOfArrayElements = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4
	header.numberOfFaces         = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4
	header.numberOfMipmapLevels  = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4
	header.bytesOfKeyValueData   = as_u32(bytes, offset, isLittleEndian) ; offset = offset + 4

	if header.numberOfMipmapLevels == 0 then
		local maxDim = math.max(header.pixelWidth, header.pixelHeight, header.pixelDepth)
		header.numberOfMipmapLevels = math.floor(math.log(maxDim, 2)) + 1
	end

	local keyValueDataBytes = string.sub(bytes, offset + 1, offset + header.bytesOfKeyValueData)
	offset = offset + header.bytesOfKeyValueData

	local keyValuePairs = {}
	local kvOffset      = 0
	while kvOffset < #keyValueDataBytes do
		local keyAndValueSize = as_u32(keyValueDataBytes, kvOffset, isLittleEndian)
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

	local mipmapLevels       = {}
	local currentPixelWidth  = header.pixelWidth
	local currentPixelHeight = header.pixelHeight
	local currentPixelDepth  = header.pixelDepth

	for level = 0, header.numberOfMipmapLevels - 1 do
		local imageSize = as_u32(bytes, offset, isLittleEndian)
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

	v[#v+1] = ui.Line({
				ui.Span('-------------------- '),
				ui.Span('header'):style(ui.Style():fg("green")),
				ui.Span(' ----------------------------'),
			})
	for _, key in ipairs(sorted) do
		local value = header[key]

		local alias = nil
		if key == 'glFormat' or key == 'glBaseInternalFormat' or key == 'glInternalFormat' then
			alias = known_formats[value]
		elseif key == 'glType' then
			alias = known_types[value]
		end
		if alias then
			alias = ui.Span(alias):style(ui.Style():fg("yellow"))
		end

		v[#v+1] = ui.Line({
					ui.Span(rpad(tostring(key), 30) .. ' '):style(ui.Style():fg("blue")),
					ui.Span(rpad(tostring(value), 12) .. ' ' .. string.format("0x%x      ", value)),
					alias,
				})
	end
	v[#v+1] = ui.Line('')

	v[#v+1] = ui.Line({
				ui.Span('------------------- '),
				ui.Span('meta data'):style(ui.Style():fg("green")),
				ui.Span(' --------------------------'),
			})
	sorted = {}
	for key in pairs(keyValuePairs) do table.insert(sorted, key) end
	table.sort(sorted)
	for _, key in ipairs(sorted) do
		local value = keyValuePairs[key]
		v[#v+1] = ui.Line({
				ui.Span(rpad(safe_ascii(key), 30) .. ' '):style(ui.Style():fg("blue")),
				ui.Span(safe_ascii(value)),
			})
	end

	v[#v+1] = ui.Line('')

	v[#v+1] = ui.Line({
					ui.Span('------------------- '),
					ui.Span('mip levels'):style(ui.Style():fg("green")),
					ui.Span(' -------------------------')
				})
	v[#v+1] = ui.Line('  mip width  height   depth  size             offset'):style(ui.Style()):fg("yellow")
	for index, mip in ipairs(mipmapLevels) do
		v[#v+1] = ui.Line({
					ui.Span(lpad(tostring(index), 5)):style(ui.Style():fg("blue")),
					ui.Span(' '          ..
						lpad(tostring(mip.width), 5)      .. ' × '        ..
						lpad(tostring(mip.height), 5)     .. ' × '        ..
						mip.depth                         .. '      '     ..
						rpad(tostring(mip.dataLength), 7) .. ' bytes at ' ..
						string.format("0x%08x",mip.dataOffset))
					})
	end

	for i = 1, job.skip do
		table.remove(v, 1)
	end

	return ya.preview_widget(job, { ui.Text(v):area(job.area):wrap(ui.Wrap.YES) })
end

function M:seek(job) require("code"):seek(job) end

return M
