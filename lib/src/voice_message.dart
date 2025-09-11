import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
// ignore: library_prefixes
import 'package:just_audio/just_audio.dart' as jsAudio;
import 'package:path_provider/path_provider.dart';
import 'package:voice_message_package/src/contact_noises.dart';
import 'package:voice_message_package/src/helpers/utils.dart';

import './helpers/widgets.dart';
import './noises.dart';
import 'helpers/colors.dart';

// ignore: must_be_immutable
class VoiceMessage extends StatefulWidget {
  VoiceMessage({
    Key? key,
    required this.me,
    this.audioSrc,
    this.audioFile,
    this.duration,
    this.formatDuration,
    this.showDuration = false,
    this.waveForm,
    this.noiseCount = 27,
    this.meBgColor = AppColors.pink,
    this.contactBgColor = const Color(0xffffffff),
    this.contactFgColor = AppColors.pink,
    this.contactCircleColor = Colors.red,
    this.mePlayIconColor = Colors.black,
    this.contactPlayIconColor = Colors.black26,
    this.radius = 12,
    this.contactPlayIconBgColor = Colors.grey,
    this.meFgColor = const Color(0xffffffff),
    this.played = false,
    this.onPlay,
    this.cacheEnabled = false,
  }) : super(key: key);

  final String? audioSrc;
  Future<File>? audioFile;
  bool cacheEnabled;
  final Duration? duration;
  final bool showDuration;
  final List<double>? waveForm;
  final double radius;

  final int noiseCount;
  final Color meBgColor,
      meFgColor,
      contactBgColor,
      contactFgColor,
      contactCircleColor,
      mePlayIconColor,
      contactPlayIconColor,
      contactPlayIconBgColor;
  final bool played, me;
  Function()? onPlay;
  String Function(Duration duration)? formatDuration;

  @override
  // ignore: library_private_types_in_public_api
  _VoiceMessageState createState() => _VoiceMessageState();
}

class _VoiceMessageState extends State<VoiceMessage>
    with SingleTickerProviderStateMixin {
  late StreamSubscription _playerStateSubscription;
  late StreamSubscription _positionSubscription;
  final AudioPlayer _player = AudioPlayer();
  final double maxNoiseHeight = 6.w(), noiseWidth = 28.5.w();
  Duration? _audioDuration;
  Duration _currentPosition = Duration.zero;
  double maxDurationForSlider = .0000001;
  bool _isPlaying = false, x2 = false, _audioConfigurationDone = false;
  bool _isDownloading = false;
  bool _isAudioAvailable = false;
  int duration = 00;
  String _remainingTime = '';
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();

    // Default formatting to display mm:ss without milliseconds
    widget.formatDuration ??= (Duration duration) {
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      String minutes = twoDigits(duration.inMinutes);
      String seconds = twoDigits(duration.inSeconds.remainder(60));
      return '$minutes:$seconds';
    };

    _checkAudioAvailability();
    _setDuration();
    _setupPlayerListeners();
  }

  void _setupPlayerListeners() {
    // Listen to player state changes
    _playerStateSubscription = _player.onPlayerStateChanged.listen((event) {
      switch (event) {
        case PlayerState.stopped:
          setState(() {
            _isPlaying = false;
            _currentPosition = Duration.zero;
          });
          break;
        case PlayerState.playing:
          setState(() => _isPlaying = true);
          break;
        case PlayerState.paused:
          setState(() => _isPlaying = false);
          break;
        case PlayerState.completed:
          _handlePlaybackComplete();
          break;
        default:
          break;
      }
    });

    // Listen to position changes with throttling
    _positionSubscription = _player.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _remainingTime = widget.formatDuration!(position);

          // Update animation only if it's configured
          if (_audioConfigurationDone &&
              _controller != null &&
              _audioDuration != null) {
            final progress =
                position.inMilliseconds / _audioDuration!.inMilliseconds;
            _controller!.value = (noiseWidth * progress).clamp(0.0, noiseWidth);
          }
        });
      }
    });
  }

  void _handlePlaybackComplete() {
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _currentPosition = Duration.zero;
        if (_audioDuration != null) {
          _remainingTime = widget.formatDuration!(_audioDuration!);
        }
      });
      _controller?.reset();
      _player.seek(Duration.zero);
    }
  }

  Future<void> _checkAudioAvailability() async {
    try {
      if (widget.audioFile != null) {
        final file = await widget.audioFile!;
        if (mounted) {
          setState(() => _isAudioAvailable = file.existsSync());
        }
      } else if (widget.audioSrc != null) {
        final response = await Dio().head(widget.audioSrc!);
        if (mounted) {
          setState(() => _isAudioAvailable = response.statusCode == 200);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isAudioAvailable = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _sizerChild(context);

  Widget _playOrDownloadButton(BuildContext context) {
    if (_isAudioAvailable) {
      return _playButton(context);
    } else {
      return _downloadButton(context);
    }
  }

  Widget _downloadButton(BuildContext context) => InkWell(
        onTap: _isDownloading
            ? null
            : () async {
                setState(() => _isDownloading = true);
                try {
                  final path = await _downloadAndCacheAudio(widget.audioSrc!);
                  if (mounted) {
                    setState(() {
                      _isAudioAvailable = true;
                      widget.audioFile = Future.value(File(path));
                    });
                    // Reconfigure duration with cached file
                    _setDuration();
                  }
                } catch (e) {
                  debugPrint("Error downloading audio: $e");
                } finally {
                  if (mounted) {
                    setState(() => _isDownloading = false);
                  }
                }
              },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.me ? widget.meFgColor : widget.contactPlayIconBgColor,
          ),
          width: 10.w(),
          height: 10.w(),
          child: _isDownloading
              ? CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.me ? widget.meFgColor : widget.contactFgColor,
                )
              : Icon(
                  Icons.download,
                  color: widget.me
                      ? widget.mePlayIconColor
                      : widget.contactPlayIconColor,
                  size: 5.w(),
                ),
        ),
      );

  Container _sizerChild(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: .8.w()),
        constraints: BoxConstraints(maxWidth: 100.w() * .8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(widget.radius),
            bottomLeft: widget.me
                ? Radius.circular(widget.radius)
                : const Radius.circular(4),
            bottomRight: !widget.me
                ? Radius.circular(widget.radius)
                : const Radius.circular(4),
            topRight: Radius.circular(widget.radius),
          ),
          color: widget.me ? widget.meBgColor : widget.contactBgColor,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w(), vertical: 2.8.w()),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _playOrDownloadButton(context),
              SizedBox(width: 3.w()),
              _durationWithNoise(context),
              SizedBox(width: 2.2.w()),
            ],
          ),
        ),
      );

  Widget _playButton(BuildContext context) => InkWell(
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.me ? widget.meFgColor : widget.contactPlayIconBgColor,
          ),
          width: 10.w(),
          height: 10.w(),
          child: InkWell(
            onTap: () =>
                !_audioConfigurationDone ? null : _changePlayingStatus(),
            child: !_audioConfigurationDone
                ? Container(
                    padding: const EdgeInsets.all(8),
                    width: 10,
                    height: 0,
                    child: CircularProgressIndicator(
                      strokeWidth: 1,
                      color:
                          widget.me ? widget.meFgColor : widget.contactFgColor,
                    ),
                  )
                : Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: widget.me
                        ? widget.mePlayIconColor
                        : widget.contactPlayIconColor,
                    size: 5.w(),
                  ),
          ),
        ),
      );

  Widget _durationWithNoise(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _noise(context),
          SizedBox(height: .3.w()),
          Row(
            children: [
              /// show played badge
              if (!widget.played)
                Widgets.circle(context, 1.5.w(),
                    widget.me ? widget.meFgColor : widget.contactCircleColor),

              /// show duration
              if (widget.showDuration && _audioDuration != null)
                Padding(
                  padding: EdgeInsets.only(left: 1.2.w()),
                  child: Text(
                    widget.formatDuration!(_audioDuration!),
                    style: TextStyle(
                      fontSize: 10,
                      color:
                          widget.me ? widget.meFgColor : widget.contactFgColor,
                    ),
                  ),
                ),
              SizedBox(width: 1.5.w()),
              SizedBox(
                width: 50,
                child: Text(
                  _remainingTime,
                  style: TextStyle(
                    fontSize: 10,
                    color: widget.me ? widget.meFgColor : widget.contactFgColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      );

  /// Audio waveform widget
  Widget _noise(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final newTHeme = theme.copyWith(
      sliderTheme: SliderThemeData(
        trackShape: CustomTrackShape(),
        thumbShape: SliderComponentShape.noThumb,
        minThumbSeparation: 0,
      ),
    );

    return Theme(
      data: newTHeme,
      child: SizedBox(
        height: 6.5.w(),
        width: noiseWidth,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            widget.me ? const Noises() : const ContactNoise(),
            if (_audioConfigurationDone && _controller != null)
              AnimatedBuilder(
                animation: _controller!,
                builder: (context, child) {
                  return Positioned(
                    left: 0,
                    child: Container(
                      width: _controller!.value,
                      height: 6.w(),
                      color: widget.me
                          ? widget.meBgColor.withOpacity(.4)
                          : widget.contactBgColor.withOpacity(.35),
                    ),
                  );
                },
              ),
            Opacity(
              opacity: .0,
              child: Container(
                width: noiseWidth,
                color: Colors.amber.withOpacity(0),
                child: Slider(
                  min: 0.0,
                  max: maxDurationForSlider,
                  onChangeStart: (_) => _onSliderStart(),
                  onChanged: (value) => _onChangeSlider(value),
                  onChangeEnd: (_) => _onSliderEnd(),
                  value: _currentPosition.inMilliseconds
                      .toDouble()
                      .clamp(0.0, maxDurationForSlider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _wasPlayingBeforeSliderChange = false;

  void _onSliderStart() {
    _wasPlayingBeforeSliderChange = _isPlaying;
    if (_isPlaying) {
      _stopPlaying();
    }
  }

  void _onSliderEnd() {
    if (_wasPlayingBeforeSliderChange) {
      _startPlaying();
    }
  }

  void _startPlaying() async {
    try {
      if (widget.cacheEnabled && widget.audioSrc != null) {
        // If cache is enabled and we have a URL, use cache
        final String cachedPath =
            await _downloadAndCacheAudio(widget.audioSrc!);
        await _playFromFile(cachedPath);
      } else {
        // Otherwise, use standard method
        if (widget.audioFile != null) {
          final String filePath = (await widget.audioFile!).path;
          debugPrint("> _startPlaying filePath: $filePath");
          await _playFromFile(filePath);
        } else if (widget.audioSrc != null) {
          await _playFromUrl(widget.audioSrc!);
        }
      }
    } catch (e) {
      debugPrint("Error starting playback: $e");
      setState(() => _isPlaying = false);
    }
  }

  // Cache management
  static final Map<String, String> _audioCache = {};

  Future<String> _downloadAndCacheAudio(String url) async {
    // Check if file is already cached
    if (_audioCache.containsKey(url)) {
      final cachedPath = _audioCache[url]!;
      if (await File(cachedPath).exists()) {
        debugPrint("Using cached audio: $cachedPath");
        return cachedPath;
      } else {
        // Cached file no longer exists, remove from cache
        _audioCache.remove(url);
      }
    }

    // Download and cache
    debugPrint("Downloading and caching audio: $url");
    final dio = Dio();
    final tempDir = await getTemporaryDirectory();

    // Create filename based on URL hash to avoid collisions
    final urlHash = url.hashCode.abs().toString();
    final extension = _getFileExtension(url);
    final tempPath = '${tempDir.path}/cached_audio_$urlHash$extension';

    try {
      await dio.download(url, tempPath);
      _audioCache[url] = tempPath;
      debugPrint("Audio cached successfully: $tempPath");
      return tempPath;
    } catch (e) {
      debugPrint("Error downloading audio for cache: $e");
      // In case of error, try to play directly from URL
      rethrow;
    }
  }

  String _getFileExtension(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final lastDot = path.lastIndexOf('.');
      if (lastDot != -1 && lastDot < path.length - 1) {
        return path.substring(lastDot);
      }
    } catch (e) {
      debugPrint("Error parsing URL for extension: $e");
    }
    return '.aac';
  }

  Future<void> _playFromFile(String path) async {
    await _player.play(DeviceFileSource(path));
  }

  Future<void> _playFromUrl(String url) async {
    await _player.play(UrlSource(url));
  }

  _stopPlaying() async {
    await _player.pause();
  }

  void _setDuration() async {
    try {
      Duration? detectedDuration;

      // Priority to user-provided duration
      if (widget.duration != null) {
        detectedDuration = widget.duration;
      } else {
        // Detect audio file duration
        final jsAudio.AudioPlayer tempPlayer = jsAudio.AudioPlayer();
        try {
          if (widget.audioFile != null) {
            String path = (await widget.audioFile!).path;
            detectedDuration = await tempPlayer.setFilePath(path);
          } else if (widget.audioSrc != null) {
            // If cache is enabled, use cached file for duration detection
            if (widget.cacheEnabled) {
              try {
                final cachedPath =
                    await _downloadAndCacheAudio(widget.audioSrc!);
                detectedDuration = await tempPlayer.setFilePath(cachedPath);
              } catch (e) {
                debugPrint(
                    "Error using cached file for duration detection, falling back to URL: $e");
                detectedDuration = await tempPlayer.setUrl(widget.audioSrc!);
              }
            } else {
              detectedDuration = await tempPlayer.setUrl(widget.audioSrc!);
            }
          }
        } finally {
          await tempPlayer.dispose();
        }
      }

      if (detectedDuration != null && mounted) {
        setState(() {
          _audioDuration = detectedDuration;
          duration = detectedDuration!.inMilliseconds;
          maxDurationForSlider = duration.toDouble();
          _remainingTime = widget.formatDuration!(detectedDuration);
        });

        _controller = AnimationController(
          vsync: this,
          duration: detectedDuration,
        );

        _completeAnimationConfiguration();
      }
    } catch (e) {
      debugPrint("Error setting duration: $e");
      if (mounted) {
        _completeAnimationConfiguration();
      }
    }
  }

  void _completeAnimationConfiguration() {
    if (mounted) {
      setState(() => _audioConfigurationDone = true);
    }
  }

  void _changePlayingStatus() async {
    if (widget.onPlay != null) widget.onPlay!();

    if (_isPlaying) {
      await _stopPlaying();
    } else {
      _startPlaying();
    }
  }

  @override
  void dispose() {
    _playerStateSubscription.cancel();
    _positionSubscription.cancel();
    _player.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onChangeSlider(double value) async {
    if (_audioDuration == null) return;

    final newPosition = Duration(milliseconds: value.round());
    await _player.seek(newPosition);

    if (mounted) {
      setState(() {
        _currentPosition = newPosition;
        _remainingTime = widget.formatDuration!(newPosition);
      });
    }
  }
}

///
class CustomTrackShape extends RoundedRectSliderTrackShape {
  ///
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    const double trackHeight = 10;
    final double trackLeft = offset.dx,
        trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}
