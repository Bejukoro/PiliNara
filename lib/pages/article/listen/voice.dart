class SpeechVoice {
  const SpeechVoice({
    required this.model,
    required this.id,
    required this.name,
    required this.gender,
    required this.style,
    required this.age,
    this.locale = '',
  });
  final String model;
  final String id;
  final String name;
  final String gender;
  final String style;
  final String age;
  final String locale;

  Map<String, String> toJson() => {
    'model': model,
    'id': id,
    'name': name,
    'gender': gender,
    'style': style,
    'age': age,
    'locale': locale,
  };
  factory SpeechVoice.fromJson(Map data) => SpeechVoice(
    model: data['model'] as String,
    id: data['id'] as String,
    name: data['name'] as String,
    gender: data['gender'] as String,
    style: data['style'] as String,
    age: data['age'] as String,
    locale: data['locale'] as String? ?? '',
  );
}
