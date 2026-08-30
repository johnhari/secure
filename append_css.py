css_content = """
/* FAQ Accordion Enhancements */
details.glass {
    transition: all 0.3s ease;
}
details.glass[open] {
    border-color: var(--bull-green);
    box-shadow: 0 0 15px rgba(0, 255, 157, 0.1);
}
details.glass summary {
    transition: color 0.3s;
}
details.glass[open] summary {
    color: var(--bull-green);
}

/* Enhanced Micro-Animations */
.cta-button {
    transition: transform 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275), box-shadow 0.3s ease;
}
.cta-button:hover {
    transform: translateY(-5px) scale(1.05);
    box-shadow: 0 15px 35px rgba(0, 255, 157, 0.6);
}

.pricing-card {
    transition: transform 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275), box-shadow 0.4s ease, border-color 0.4s;
}
.pricing-card:hover {
    transform: translateY(-15px) scale(1.02);
}
"""

with open(r'c:\Users\PUTIN\Desktop\ADVANCEORDERFLOW\marketing\style.css', 'a', encoding='utf-8') as f:
    f.write("\n" + css_content + "\n")

print("CSS appended.")
