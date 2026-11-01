import 'package:flutter/material.dart';

import '../data/security_questions.dart';
import 'auth_widgets.dart';

class SecurityQuestionsController {
  final selections = List<String?>.filled(3, null);
  final custom = List.generate(3, (_) => TextEditingController());
  final answers = List.generate(3, (_) => TextEditingController());

  String question(int index) => selections[index] == customSecurityQuestion
      ? custom[index].text.trim()
      : selections[index] ?? '';

  List<Map<String, String>> get values => List.generate(
      3,
      (index) => {
            'question': question(index),
            'answer': answers[index].text.trim(),
          });

  String? validateQuestion(int index) {
    final value = question(index);
    if (value.length < 5 || value.length > 200) {
      return 'Enter a question of 5 to 200 characters.';
    }
    if (List.generate(3, question)
            .where((other) =>
                normalizeSecurityQuestion(other) ==
                normalizeSecurityQuestion(value))
            .length >
        1) {
      return 'Choose three different questions.';
    }
    return null;
  }

  void clear() {
    selections.fillRange(0, 3, null);
    for (final field in [...custom, ...answers]) {
      field.clear();
    }
  }

  void dispose() {
    for (final field in [...custom, ...answers]) {
      field.dispose();
    }
  }
}

/// Shared by optional registration and authenticated management.
class SecurityQuestionsForm extends StatefulWidget {
  const SecurityQuestionsForm({required this.controller, super.key});
  final SecurityQuestionsController controller;

  @override
  State<SecurityQuestionsForm> createState() => _SecurityQuestionsFormState();
}

class _SecurityQuestionsFormState extends State<SecurityQuestionsForm> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Column(children: [
      for (var index = 0; index < 3; index++) ...[
        FieldLabel('Question ${index + 1}'),
        DropdownButtonFormField<String>(
          key: ValueKey('question-choice-$index'),
          initialValue: controller.selections[index],
          isExpanded: true,
          decoration:
              const InputDecoration(hintText: 'Select a security question'),
          items: [...securityQuestionPresets, customSecurityQuestion]
              .map(
                (question) => DropdownMenuItem(
                    value: question,
                    child: Text(question, overflow: TextOverflow.ellipsis)),
              )
              .toList(),
          validator: (_) => controller.selections[index] == null
              ? 'Select a security question.'
              : controller.validateQuestion(index),
          onChanged: (value) => setState(() {
            controller.selections[index] = value;
            controller.custom[index].clear();
            controller.answers[index].clear();
          }),
        ),
        if (controller.selections[index] == customSecurityQuestion) ...[
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('custom-question-$index'),
            controller: controller.custom[index],
            maxLength: 200,
            validator: (_) => controller.validateQuestion(index),
            decoration:
                const InputDecoration(hintText: 'Enter your custom question'),
          ),
        ],
        const SizedBox(height: 12),
        FieldLabel('Answer ${index + 1}'),
        PasswordField(
          key: ValueKey('question-answer-$index'),
          controller: controller.answers[index],
          hintText: 'Enter answer ${index + 1}',
          validator: (value) =>
              (value ?? '').trim().isEmpty || value!.trim().length > 200
                  ? 'Enter an answer of 1 to 200 characters.'
                  : null,
        ),
        const SizedBox(height: 20),
      ],
    ]);
  }
}
