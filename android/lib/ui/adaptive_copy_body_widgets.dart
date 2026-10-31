// Small widgets of the adaptive copy trainer. Split out of
// adaptive_copy_body.dart; same library.
part of 'adaptive_copy_body.dart';


class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) =>
      AppButton(label: label, onTap: onTap, color: AppColors.of(context).info);
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => AppButton(
      label: label, onTap: onTap, color: AppColors.of(context).info, primary: false);
}
