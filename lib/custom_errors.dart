class RateLimitError {
  late int remainingMinutes;
  RateLimitError(this.remainingMinutes);

  @override
  String toString() =>
      'Rate limit reached - try again in $remainingMinutes minutes';
}
