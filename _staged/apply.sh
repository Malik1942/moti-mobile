#!/bin/bash
# Applies the temporal-parsing refactor staged files into the live source tree,
# then regenerates the Xcode project.
# Run from the repo root: bash _staged/apply.sh

set -e
cd "$(dirname "$0")/.."

echo "Applying staged service files..."
cp _staged/TaskUnderstandingService.swift         Moti/Services/TaskUnderstandingService.swift
cp _staged/RuleBasedTaskUnderstandingService.swift Moti/Services/RuleBasedTaskUnderstandingService.swift
cp _staged/MockSLMTaskUnderstandingService.swift   Moti/Services/MockSLMTaskUnderstandingService.swift
cp _staged/FoundationModelsTaskUnderstandingService.swift Moti/Services/FoundationModelsTaskUnderstandingService.swift
cp _staged/project.yml project.yml

echo "Regenerating Xcode project..."
xcodegen generate

echo ""
echo "Done. Files applied:"
echo "  Moti/Services/TaskUnderstandingService.swift"
echo "  Moti/Services/RuleBasedTaskUnderstandingService.swift"
echo "  Moti/Services/MockSLMTaskUnderstandingService.swift"
echo "  Moti/Services/FoundationModelsTaskUnderstandingService.swift"
echo "  project.yml"
echo ""
echo "New files already in place (created by Claude Code):"
echo "  Moti/Models/Temporal/TemporalInterpretation.swift"
echo "  Moti/Models/Temporal/ResolverPath.swift"
echo "  Moti/Models/Temporal/TemporalResolution.swift"
echo "  Moti/Services/Temporal/SemanticBias.swift"
echo "  Moti/Services/Temporal/DeterministicPreClassifier.swift"
echo "  Moti/Services/Temporal/SemanticContextResolver.swift"
echo "  Moti/Services/Temporal/LLMTiebreaker.swift"
echo "  Moti/Services/Temporal/TemporalResolver.swift"
echo "  Moti/Services/Temporal/DateResolverTemporalParse+TemporalResolution.swift"
echo "  MotiTests/TemporalResolverTests.swift"
echo ""
echo "Open Moti.xcodeproj in Xcode to build and run the test suite."
