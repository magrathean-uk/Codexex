---
version: alpha
name: Codexex
description: Compact macOS menu bar design with soft glass cards, mono quota figures, and cool blue or violet usage accents.
colors:
  background: "#F5F7FB"
  background-alt: "#EDEFF5"
  surface: "#FFFFFF"
  surface-alt: "#F1F4F9"
  primary: "#3587ED"
  secondary: "#A760D6"
  tertiary: "#49C9D6"
  text: "#111827"
  text-muted: "#5F6B7A"
  success: "#59C576"
  warning: "#D29A3A"
  danger: "#C86464"
typography:
  display-lg:
    fontFamily: "SF Pro Display, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: "34px"
    letterSpacing: "-0.02em"
  headline-md:
    fontFamily: "SF Pro Display, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 600
    lineHeight: "24px"
    letterSpacing: "0em"
  body-md:
    fontFamily: "SF Pro Text, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: "20px"
    letterSpacing: "0em"
  label-sm:
    fontFamily: "SF Pro Text, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: "16px"
    letterSpacing: "0.02em"
  mono-sm:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: "20px"
    letterSpacing: "0em"
rounded:
  sm: "12px"
  md: "14px"
  lg: "20px"
  xl: "24px"
  full: "999px"
spacing:
  xs: "6px"
  sm: "10px"
  md: "12px"
  lg: "14px"
  xl: "18px"
  xxl: "24px"
components:
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    typography: "{typography.body-md}"
    rounded: "{rounded.lg}"
    padding: "{spacing.lg}"
  card-inset:
    backgroundColor: "{colors.surface-alt}"
    textColor: "{colors.text}"
    typography: "{typography.body-md}"
    rounded: "{rounded.md}"
    padding: "{spacing.md}"
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#08131F"
    typography: "{typography.body-md}"
    rounded: "{rounded.md}"
    padding: "{spacing.md}"
    height: "42px"
  quota-chip:
    backgroundColor: "{colors.surface-alt}"
    textColor: "#6B2CA0"
    typography: "{typography.label-sm}"
    rounded: "{rounded.full}"
    padding: "{spacing.sm}"
---

## Overview
Codexex should feel like a polished macOS utility, not a full dashboard. It is compact, calm, and glass-forward, with precise numeric emphasis and restrained color coding.

## Colors
The base is pale neutral glass with dark text. Daily quota views lean blue, weekly and monthly history views can lean violet, and supportive cyan can appear in secondary highlights. Positive state should read green without taking over the interface.

## Typography
Use clean San Francisco hierarchy for labels and headings. Quota values, resets, and forecast numbers should use monospaced digits to reinforce precision.

## Layout
The popup and settings views are narrow, card-based, and vertically stacked. Peaks, Cycle, and Month history modes share the same compact space without turning into a full analytics surface.

## Elevation & Depth
Depth comes from translucent white cards, subtle borders, and very soft shadows. Insets are quieter than primary cards and should feel slightly recessed.

## Shapes
Large rounded glass cards are the default container shape. Small inset chips and stat rows use tighter radii, while capsules are reserved for compact indicators.

## Components
Main surfaces are glass cards. Forecast rows and usage summaries often use inset cards. Segmented history controls stay compact, while quota markers should stay short and readable.

## Do's and Don'ts
- Do keep numeric information visually precise.
- Do use accent colors to distinguish limit buckets, not to decorate empty space.
- Don't turn the popup into a dense analytics grid.
- Don't add heavy shadow or dark chrome that fights the macOS glass treatment.
