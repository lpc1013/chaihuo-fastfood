extends Node
## 音乐自检：把三首 BGM 烘成 wav 落到 tools/_scratch/，并打印时长/峰值/RMS/过零率。
## 过零率是"噪声还是乐音"的粗判据：白噪声约 0.5，有音高的乐音通常远低于它。
##   godot --headless --path <项目> -- --test=music

func run(_m: Node) -> void:
	for id in Music.TRACKS.keys():
		var wav: AudioStreamWAV = Music.bake(id)
		var data: PackedByteArray = wav.data
		var n := data.size() / 2
		var peak := 0.0
		var sum2 := 0.0
		var zc := 0
		var prev_sign := 0
		var pcm := PackedFloat32Array()
		pcm.resize(n)
		for i in n:
			var s := int(data[i * 2]) | (int(data[i * 2 + 1]) << 8)
			if s > 32767:
				s -= 65536
			var v := float(s) / 32768.0
			pcm[i] = v
			peak = maxf(peak, absf(v))
			sum2 += v * v
			var sg := 1 if v > 0.0 else (-1 if v < 0.0 else 0)
			if sg != 0 and prev_sign != 0 and sg != prev_sign:
				zc += 1
			if sg != 0:
				prev_sign = sg
		var rms := sqrt(sum2 / maxf(1.0, float(n)))
		var out := "user://music_%s.wav" % id
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_wav_bytes(wav))
			f.close()
		print("MUSIC %s dur=%.2fs peak=%.3f rms=%.4f zcr=%.4f %s" % [
			id, float(n) / float(wav.mix_rate), peak, rms, float(zc) / float(maxi(1, n)), out])
	print("MUSICCHECK DONE")
	get_tree().quit(0)

## AudioStreamWAV 没有"导出成文件"的接口，自己拼一个 44 字节的 RIFF 头。
func _wav_bytes(wav: AudioStreamWAV) -> PackedByteArray:
	var rate := wav.mix_rate
	var chans := 2 if wav.stereo else 1
	var block := chans * 2
	var body := wav.data
	var out := PackedByteArray()
	out.resize(44 + body.size())
	_put_str(out, 0, "RIFF")
	_put32(out, 4, 36 + body.size())
	_put_str(out, 8, "WAVE")
	_put_str(out, 12, "fmt ")
	_put32(out, 16, 16)
	out[20] = 1
	out[22] = chans
	_put32(out, 24, rate)
	_put32(out, 28, rate * block)
	out[32] = block
	out[34] = 16
	_put_str(out, 36, "data")
	_put32(out, 40, body.size())
	for i in body.size():
		out[44 + i] = body[i]
	return out

func _put_str(buf: PackedByteArray, off: int, s: String) -> void:
	for i in 4:
		buf[off + i] = s.unicode_at(i)

func _put32(buf: PackedByteArray, off: int, v: int) -> void:
	buf[off] = v & 0xFF
	buf[off + 1] = (v >> 8) & 0xFF
	buf[off + 2] = (v >> 16) & 0xFF
	buf[off + 3] = (v >> 24) & 0xFF
