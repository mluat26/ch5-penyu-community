//
//  CreateHatcheryShape.swift
//  community-challenge
//
//  Created by Jason Marsellino on 11/08/26.
//


//
//  CreateHatcheryShape.swift
//  community-challenge
//

import SwiftUI

struct CreateHatcheryShape: View {
    
    @State private var selectedShape: HatcheryShape = .rectangle
    
    var body: some View {
        ZStack {
            
            // Background
            Image("TurtleBG")
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // Header
            
                HStack {
                    Button {
                        // Back action
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.black)
                    }
                    
                    Spacer()
                    
                    Text("Create Hatchery")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .opacity(0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                
                // Title
                VStack(spacing: 8) {
                    Text("Choose hatchery shape")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    Text("Select the shape that best\nmatches your hatchery.")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)
                
                // Cards
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 14
                ) {
                    ForEach(HatcheryShape.allCases) { shape in
                        ShapeSelectionCard(
                            shape: shape,
                            isSelected: selectedShape == shape
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedShape = shape
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                
                Spacer()
                
                // Turtle trail
                ZStack {
                    TurtleTrailShape()
                        .stroke(
                            Color.green.opacity(0.75),
                            style: StrokeStyle(
                                lineWidth: 2,
                                lineCap: .round,
                                dash: [8, 7]
                            )
                        )
                    
                    HStack {
                        Image(systemName: "tortoise.fill")
                            .font(.title2)
                            .foregroundStyle(Color.green)
                        
                        Spacer()
                    }
                    .padding(.leading, 54)
                }
                .frame(height: 80)
                
                // Next
                Button {
                    // Navigate to dimensions
                } label: {
                    Text("Next")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            Capsule()
                                .fill(Color.green)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.light)
    }
}


// MARK: - Shape Selection Card

private struct ShapeSelectionCard: View {
    
    let shape: HatcheryShape
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                
                ShapePreview(shape: shape)
                    .frame(height: 72)
                
                Text(shape.rawValue.capitalized)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 158)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        isSelected
                        ? Color.green.opacity(0.10)
                        : Color.white.opacity(0.82)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        isSelected
                        ? Color.green
                        : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Shape Preview

private struct ShapePreview: View {
    
    let shape: HatcheryShape
    
    var body: some View {
        switch shape {
            
        
        case .square:
            Rectangle()
                .fill(Color.gray.opacity(0.18))
                .overlay {
                    Rectangle()
                        .stroke(
                            Color.gray.opacity(0.25),
                            lineWidth: 1
                        )
                }
                .frame(width: 52, height: 52)
        
        case .rectangle:
            Rectangle()
                .fill(Color.gray.opacity(0.18))
                .overlay {
                    Rectangle()
                        .stroke(
                            Color.gray.opacity(0.25),
                            lineWidth: 1
                        )
                }
                .frame(width: 97, height: 49)
            
        
            
        case .circle:
            Circle()
                .fill(Color.gray.opacity(0.12))
                .overlay {
                    Circle()
                        .stroke(
                            Color.gray.opacity(0.25),
                            lineWidth: 1
                        )
                }
                .frame(width: 54, height: 54)
        }
    }
}


// MARK: - Turtle Trail

private struct TurtleTrailShape: Shape {
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        
        path.move(
            to: CGPoint(
                x: 0,
                y: height * 0.65
            )
        )
        
        path.addCurve(
            to: CGPoint(
                x: width * 0.35,
                y: height * 0.65
            ),
            control1: CGPoint(
                x: width * 0.12,
                y: height * 0.45
            ),
            control2: CGPoint(
                x: width * 0.22,
                y: height * 0.85
            )
        )
        
        path.addCurve(
            to: CGPoint(
                x: width * 0.55,
                y: height * 0.25
            ),
            control1: CGPoint(
                x: width * 0.43,
                y: height * 0.35
            ),
            control2: CGPoint(
                x: width * 0.52,
                y: height * 0.05
            )
        )
        
        path.addCurve(
            to: CGPoint(
                x: width * 0.75,
                y: height * 0.65
            ),
            control1: CGPoint(
                x: width * 0.58,
                y: height * 0.48
            ),
            control2: CGPoint(
                x: width * 0.68,
                y: height * 0.85
            )
        )
        
        path.addCurve(
            to: CGPoint(
                x: width,
                y: height * 0.55
            ),
            control1: CGPoint(
                x: width * 0.87,
                y: height * 0.40
            ),
            control2: CGPoint(
                x: width * 0.93,
                y: height * 0.60
            )
        )
        
        return path
    }
}


// MARK: - Preview

#Preview {
    CreateHatcheryShape()
}
