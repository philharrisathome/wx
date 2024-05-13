local radio = require('radio')

if #arg < 2 then
    io.stderr:write("Usage: " .. arg[0] .. " <FM radio frequency> <Output filename>\n")
    os.exit(1)
end

local frequency = tonumber(arg[1])
local output_file = tostring(arg[2])
local rf_bandwidth = 350e3
local sample_rate = 110250
local oversample = 10
local tune_offset = -100e3
local if_bandwidth = 40e3
local audio_pipe = '/tmp/noaa_audio_pipe'

io.stderr:write("Recording from " .. frequency / 1e6 .. " MHz to " .. output_file .. "\n")

-- Blocks
-- local source = radio.RtlSdrSource(frequency + tune_offset, sample_rate*oversample, {bandwidth = rf_bandwidth, rf_gain = 50 - 20})	-- With LNA
local source = radio.RtlSdrSource(frequency + tune_offset, sample_rate*oversample, {bandwidth = rf_bandwidth, rf_gain = 50})		-- Without LNA
local raw_sink = radio.RawFileSink('noaa.raw')
local tuner = radio.TunerBlock(tune_offset, if_bandwidth, oversample, {num_taps=64})
local fm_demod = radio.FrequencyDiscriminatorBlock(1.00) -- Usually 1.25
local af_filter = radio.LowpassFilterBlock(128, 4.5e3)
local af_downsampler = radio.DownsamplerBlock(10)		-- Need 11025 as output rate
--local audio_sink = radio.PulseAudioSink(1)
local af_gain = radio.MultiplyConstantBlock(3.0)	-- Reduce quantisation noise in WAV file
local wav_sink = radio.WAVFileSink(output_file,1,16)
local pipe_sink = radio.RealFileSink(audio_pipe,'s16le')

-- Connections
local top = radio.CompositeBlock()
top:connect(source, tuner, fm_demod, af_filter, af_downsampler, af_gain, wav_sink)
-- top:connect(source, raw_sink)
-- top:connect(af_downsampler, pipe_sink)

top:run()
