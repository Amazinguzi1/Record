import 'package:flutter/material.dart';

/// 可选图标集合。数据库里存的是这里的 key（字符串），
/// 而不是 IconData 的 codePoint —— 这样 release 构建时图标不会被 tree-shaking 移除。
const Map<String, IconData> kCategoryIcons = {
  'food': Icons.fastfood,
  'car': Icons.directions_car,
  'shop': Icons.shopping_cart,
  'game': Icons.gamepad,
  'salary': Icons.monetization_on,
  'gift': Icons.card_giftcard,
  'work': Icons.work,
  'home': Icons.home,
  'phone': Icons.phone_iphone,
  'medical': Icons.local_hospital,
  'edu': Icons.school,
  'travel': Icons.flight,
  'sport': Icons.fitness_center,
  'coffee': Icons.local_cafe,
  'pet': Icons.pets,
  'other': Icons.category,
};

IconData iconOf(String key) => kCategoryIcons[key] ?? Icons.category;
