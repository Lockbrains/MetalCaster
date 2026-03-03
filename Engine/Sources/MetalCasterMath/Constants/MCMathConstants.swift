import Foundation

// MARK: - Conversion Constants

public let mc_deg2Rad: Float = .pi / 180.0
public let mc_rad2Deg: Float = 180.0 / .pi
public let mc_deg2RadD: Double = .pi / 180.0
public let mc_rad2DegD: Double = 180.0 / .pi

// MARK: - Precision Constants

public let mc_epsilon: Float = 1.0e-6
public let mc_epsilonD: Double = 1.0e-12
public let mc_epsilonSq: Float = 1.0e-12

// MARK: - Common Constants

public let mc_goldenRatio: Float = 1.6180339887
public let mc_sqrt2: Float = 1.4142135624
public let mc_sqrt3: Float = 1.7320508076
public let mc_halfPi: Float = .pi / 2.0
public let mc_twoPi: Float = .pi * 2.0
public let mc_invPi: Float = 1.0 / .pi

// MARK: - Magnitude Thresholds

/// Smallest normal Float value (~1.175e-38).
public let mc_floatMinNormal: Float = Float.leastNormalMagnitude

/// Largest finite Float value (~3.403e+38).
public let mc_floatMaxFinite: Float = Float.greatestFiniteMagnitude

/// Smallest normal Double value (~2.225e-308).
public let mc_doubleMinNormal: Double = Double.leastNormalMagnitude

/// Largest finite Double value (~1.798e+308).
public let mc_doubleMaxFinite: Double = Double.greatestFiniteMagnitude
