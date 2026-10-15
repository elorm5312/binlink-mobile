import 'package:audioplayers/audioplayers.dart';

/// Short one-shot UI sounds (success chime, message pop). Looping alerts
/// (new job, incoming call) own their own players.
class SoundFx {
  SoundFx._();

  static final _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  static const success = 'sounds/success.wav';
  static const message = 'sounds/message.wav';

  static Future<void> play(String asset, {double volume = 0.8}) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(asset), volume: volume);
    } catch (_) {}
  }
}
