enum AccountPriorityLevel {
  reserve(0),
  normal(1),
  primary(2);

  const AccountPriorityLevel(this.storedValue);

  final int storedValue;

  static AccountPriorityLevel fromStoredValue(int value) {
    if (value >= primary.storedValue) {
      return primary;
    }
    if (value <= reserve.storedValue) {
      return reserve;
    }
    return normal;
  }
}

const defaultAccountPriority = 1;

int normalizeAccountPriority(int value) {
  return AccountPriorityLevel.fromStoredValue(value).storedValue;
}
