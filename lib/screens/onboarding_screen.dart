import 'package:flutter/material.dart';

import '../services/onboarding_service.dart';
import '../theme.dart';

/// One page of the walkthrough.
class _Slide {
  final String emoji;
  final String title;
  final String body;
  final Color colour;
  const _Slide({
    required this.emoji,
    required this.title,
    required this.body,
    required this.colour,
  });
}

const List<_Slide> _slides = [
  _Slide(
    emoji: '🔥',
    title: 'Welcome to Arena',
    body: 'Arena is where people argue it out — politics, science, movies, '
        'sport, anything. Pick a debate and jump straight in.',
    colour: AppColors.primary,
  ),
  _Slide(
    emoji: '⚔️',
    title: 'Pick your side',
    body: 'Every room has a topic. Join as For or Against and your messages '
        'get colour-coded so everyone can see where you stand — or just watch '
        'quietly first.',
    colour: AppColors.forSide,
  ),
  _Slide(
    emoji: '💬',
    title: 'Debate live',
    body: 'Messages land in real time. Swipe a message to reply to it, react '
        'with an emoji, and get a notification when someone answers you.',
    colour: AppColors.secondary,
  ),
  _Slide(
    emoji: '🏆',
    title: 'Vote who won',
    body: 'When the dust settles, vote on who made the better case. And every '
        'day Arena drops a fresh topic of the day for everyone to fight over.',
    colour: AppColors.accent,
  ),
];

/// The first-run walkthrough. Shown once on a new phone (and again on demand
/// from Settings → "Replay walkthrough").
///
/// Deliberately self-contained: it's a plain screen that pops itself when it's
/// done, so it can't interfere with the login / verify-email routing in
/// `main.dart`.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _slides.length - 1;

  Future<void> _finish() async {
    await OnboardingService.markSeen();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip — always available, so nobody is ever stuck here.
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: AppColors.textGrey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: active ? 22 : 8,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: ElevatedButton(
                onPressed: _next,
                child: Text(_isLast ? 'Start debating' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    // Centre the slide in whatever space the PageView gives us, but stay
    // scrollable so nothing is ever cut off on a short screen or at a large
    // font scale.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
          Container(
            height: 148,
            width: 148,
            decoration: BoxDecoration(
              color: slide.colour.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(slide.emoji, style: const TextStyle(fontSize: 68)),
          ),
          const SizedBox(height: 36),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              color: AppColors.textGrey,
            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
