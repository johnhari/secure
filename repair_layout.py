
import os

path = r"c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\orderflow\lib\presentation\screens\chart_screen.dart"

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix the animated builder section
# Search for the block starting with Column( on line 1835
old_block = """        return Transform.scale(
          scale: pulseValue,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (customTag.isNotEmpty)
                _buildSignalTag(customTag, borderColor ?? Colors.white),
              Container(
                padding: EdgeInsets.all(basePadding),
                decoration: BoxDecoration(
                  color: isImbalance ? Colors.white.withValues(alpha: 0.8) : color,
                  shape: BoxShape.circle,
                  border: isBigSignal 
                      ? Border.all(color: borderColor ?? Colors.white54, width: borderWidth + 1) 
                      : Border.all(color: borderColor ?? Colors.white10, width: borderWidth),
                  boxShadow: isBigSignal ? [
                    BoxShadow(
                      color: (borderColor ?? Colors.white).withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: spread,
                    )
                  ] : [
                    BoxShadow(
                      color: (isBuyer ? AppTheme.bullColor : AppTheme.bearColor).withValues(alpha: glowIntensity),
                      blurRadius: 20,
                      spreadRadius: spread,
                    ),
                  ],
                ),
                child: !showLabel 
                  ? const SizedBox.shrink()
                  : Center(
                      child: _AnimatedOrderflowCounter(
                        count: count,
                        isImbalance: isImbalance,
                        isBig: isBigSignal,
                        textColor: isImbalance ? Colors.black : Colors.white,
                        scale: finalRelativeScale,
                      ),
                    ),
              ),
              // ADDED: Wave/Ripple Effect for Advanced Signals
              if (isBigSignal)
                ..._buildSpecialEffectLayers(customTag, vibrantColor, finalRelativeScale),
            ],
          ),
        );"""

new_block = """        return Transform.scale(
          scale: pulseValue,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 1. Primary bubble visual
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (customTag.isNotEmpty)
                    _buildSignalTag(customTag, borderColor ?? Colors.white),
                  Container(
                    padding: EdgeInsets.all(basePadding),
                    decoration: BoxDecoration(
                      color: isImbalance ? Colors.white.withValues(alpha: 0.8) : color,
                      shape: BoxShape.circle,
                      border: isBigSignal 
                          ? Border.all(color: borderColor ?? Colors.white54, width: borderWidth + 1) 
                          : Border.all(color: borderColor ?? Colors.white10, width: borderWidth),
                      boxShadow: isBigSignal ? [
                        BoxShadow(
                          color: (borderColor ?? Colors.white).withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: spread,
                        )
                      ] : [
                        BoxShadow(
                          color: (isBuyer ? AppTheme.bullColor : AppTheme.bearColor).withValues(alpha: glowIntensity),
                          blurRadius: 20,
                          spreadRadius: spread,
                        ),
                      ],
                    ),
                    child: !showLabel 
                      ? const SizedBox.shrink()
                      : Center(
                          child: _AnimatedOrderflowCounter(
                            count: count,
                            isImbalance: isImbalance,
                            isBig: isBigSignal,
                            textColor: isImbalance ? Colors.black : Colors.white,
                            scale: finalRelativeScale,
                          ),
                        ),
                  ),
                ],
              ),
              // 2. Special effect layers (Positioned)
              if (isBigSignal)
                ..._buildSpecialEffectLayers(customTag, vibrantColor, finalRelativeScale),
            ],
          ),
        );"""

# Relaxed matching (whitespace normalized)
content_norm = " ".join(content.split())
old_block_norm = " ".join(old_block.split())

if old_block_norm in content_norm:
    # Use exact line numbers or robust regex
    import re
    
    # This is a bit risky but we have the content
    content = content.replace(old_block, new_block)
    
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("SUCCESS: Fixed layout in chart_screen.dart")
else:
    print("ERROR: Could not find block in chart_screen.dart")
