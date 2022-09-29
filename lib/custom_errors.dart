class RateLimitError {
  late int remainingMinutes;
  RateLimitError(this.remainingMinutes);

  @override
  String toString() =>
      'Too many requests (rate limited) - try again in $remainingMinutes minutes';
}
