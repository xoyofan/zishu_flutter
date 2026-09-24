class C {
  const C({String? a}) : a = a == '' ? null : a;
  final String? a;
}
void main() {
  const c = C(a: 'x');
  print(c.a);
}
