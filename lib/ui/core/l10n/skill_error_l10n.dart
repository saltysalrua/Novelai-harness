import '../../../core/harness/skills/skill_format_exception.dart';
import '../../../l10n/app_localizations.dart';

String skillErrorText(AppLocalizations l10n, Object error) {
  if (error is! SkillFormatException) {
    return error is FormatException
        ? error.message
        : l10n.skillOperationFailed(error.toString());
  }
  return switch (error.code) {
    SkillFormatError.packageTooLarge => l10n.skillErrorPackageTooLarge,
    SkillFormatError.instructionsTooLarge =>
      l10n.skillErrorInstructionsTooLarge,
    SkillFormatError.fileType => l10n.skillErrorFileType,
    SkillFormatError.tooManyEntries => l10n.skillErrorTooManyEntries,
    SkillFormatError.specialFile => l10n.skillErrorSpecialFile,
    SkillFormatError.duplicatePath => l10n.skillErrorDuplicatePath(
      error.detail,
    ),
    SkillFormatError.sizeLimit => l10n.skillErrorSizeLimit,
    SkillFormatError.encrypted => l10n.skillErrorEncrypted,
    SkillFormatError.missingData => l10n.skillErrorMissingData,
    SkillFormatError.compression => l10n.skillErrorCompression,
    SkillFormatError.checksum => l10n.skillErrorChecksum,
    SkillFormatError.invalidZip => l10n.skillErrorInvalidZip,
    SkillFormatError.directory => l10n.skillErrorDirectory,
    SkillFormatError.linkFile => l10n.skillErrorLinkFile,
    SkillFormatError.pathEscape => l10n.skillErrorPathEscape,
    SkillFormatError.packageLimit => l10n.skillErrorPackageLimit,
    SkillFormatError.specialEntry => l10n.skillErrorSpecialEntry,
    SkillFormatError.oneEntry => l10n.skillErrorOneEntry,
    SkillFormatError.invalidId => l10n.skillErrorInvalidId,
    SkillFormatError.description => l10n.skillErrorDescription,
    SkillFormatError.duplicateFile => l10n.skillErrorDuplicateFile(
      error.detail,
    ),
    SkillFormatError.fileLimit => l10n.skillErrorFileLimit,
    SkillFormatError.treeConflict => l10n.skillErrorTreeConflict,
    SkillFormatError.relativePath => l10n.skillErrorRelativePath,
    SkillFormatError.pathDepth => l10n.skillErrorPathDepth,
    SkillFormatError.unsafePath => l10n.skillErrorUnsafePath(error.detail),
    SkillFormatError.storageId => l10n.skillErrorStorageId,
    SkillFormatError.missingPackage => l10n.skillErrorMissingPackage,
    SkillFormatError.missingResource => l10n.skillErrorMissingResource,
    SkillFormatError.readLink => l10n.skillErrorReadLink,
    SkillFormatError.resourceEscape => l10n.skillErrorResourceEscape,
    SkillFormatError.readSize => l10n.skillErrorReadSize,
    SkillFormatError.unpackedSize => l10n.skillErrorUnpackedSize,
    SkillFormatError.yamlDelimiter => l10n.skillErrorYamlDelimiter,
    SkillFormatError.yamlInvalid => l10n.skillErrorYamlInvalid(error.detail),
    SkillFormatError.yamlMapping => l10n.skillErrorYamlMapping,
    SkillFormatError.yamlDepth => l10n.skillErrorYamlDepth,
    SkillFormatError.yamlKeys => l10n.skillErrorYamlKeys,
    SkillFormatError.yamlValue => l10n.skillErrorYamlValue,
    SkillFormatError.yamlString => l10n.skillErrorYamlString(error.detail),
    SkillFormatError.yamlBoolean => l10n.skillErrorYamlBoolean,
  };
}
